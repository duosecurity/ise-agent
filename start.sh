#!/usr/bin/env bash
#
# ISE Agent start script.
#
# Thin wrapper: detects docker/podman, then delegates interactive setup to
# scripts that run inside the agent container. The container handles all
# credential encryption, .env manipulation, and ISE connectivity checks.
#
# Usage:
#   ./start.sh                  # Normal start (runs first-run setup if needed)
#   ./start.sh --reconfigure    # Re-enter ISE credentials
#   ./start.sh --enable-pxgrid  # Enable real-time session monitoring via pxGrid
#   ./start.sh --disable-pxgrid # Revert to MnT polling for sessions
#   ./start.sh --stop           # Stop the agent
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

CREDENTIALS_FILE="./certs/.credentials.enc"
KEY_FILE="./certs/private.pem.key"
CERT_FILE="./certs/certificate.pem.crt"

IMAGE="ghcr.io/duosecurity/ise-agent:latest"
CONTAINER_NAME=$(grep 'container_name:' docker-compose.yml | head -1 | awk '{print $2}' 2>/dev/null || echo "ise-agent")

# -- Detect container runtime (docker or podman) --

detect_runtime() {
  if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    echo "docker"
  elif command -v podman &>/dev/null; then
    echo "podman"
  else
    echo ""
  fi
}

RUNTIME="$(detect_runtime)"

if [[ "${RUNTIME}" == "docker" ]]; then
  COMPOSE_CMD="docker compose"
elif [[ "${RUNTIME}" == "podman" ]] && podman compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="podman compose"
elif [[ "${RUNTIME}" == "podman" ]] && command -v podman-compose &>/dev/null; then
  COMPOSE_CMD="podman-compose"
else
  COMPOSE_CMD=""
fi

# -- Container helpers --

check_prerequisites() {
  if [[ -z "${RUNTIME}" ]]; then
    echo "Error: No container runtime found. Install docker or podman." >&2
    exit 1
  fi
  for f in "${KEY_FILE}" "${CERT_FILE}" ".env"; do
    if [[ ! -f "${f}" ]]; then
      echo "Error: ${f} not found. Make sure you've extracted the full agent package." >&2
      exit 1
    fi
  done
}

run_in_container() {
  # Run a one-off container with certs + .env mounted so setup scripts
  # can read/write both without the host needing to know the layout.
  local script="$1"
  shift
  local tty_flag
  tty_flag=$([ -t 0 ] && echo "-t" || echo "")
  ${RUNTIME} run --rm -i ${tty_flag} \
    -v "$(pwd)/certs:/app/certs" \
    -v "$(pwd)/.env:/app/.env" \
    --entrypoint python "${IMAGE}" -u "/app/${script}" "$@"
}

compose_restart() {
  ${COMPOSE_CMD} down 2>/dev/null || true
  ${COMPOSE_CMD} up -d
  echo "View logs: ${RUNTIME} logs -f ${CONTAINER_NAME}"
}

# -- Main --

ACTION=""
for arg in "$@"; do
  case "${arg}" in
    --reconfigure) ACTION="reconfigure" ;;
    --stop) ACTION="stop" ;;
    --enable-pxgrid) ACTION="enable-pxgrid" ;;
    --disable-pxgrid) ACTION="disable-pxgrid" ;;
    *) echo "Unknown option: ${arg}" >&2; exit 1 ;;
  esac
done

if [[ -z "${COMPOSE_CMD}" ]]; then
  echo "Error: No container runtime found. Install docker or podman." >&2
  exit 1
fi

if [[ "${ACTION}" == "stop" ]]; then
  echo "Stopping ISE agent..."
  ${COMPOSE_CMD} down
  exit 0
fi

check_prerequisites

if [[ "${ACTION}" == "enable-pxgrid" ]]; then
  run_in_container setup_pxgrid.py enable
  compose_restart
  exit 0
fi

if [[ "${ACTION}" == "disable-pxgrid" ]]; then
  run_in_container setup_pxgrid.py disable
  compose_restart
  exit 0
fi

FIRST_RUN=0
if [[ "${ACTION}" == "reconfigure" ]] || [[ ! -f "${CREDENTIALS_FILE}" ]]; then
  [[ ! -f "${CREDENTIALS_FILE}" ]] && FIRST_RUN=1
  echo ""
  echo "Running ISE credential setup inside container..."
  run_in_container setup_credentials.py
fi

# On first run only, also ask whether to enable pxGrid.
if [[ "${FIRST_RUN}" == "1" ]] && ! grep -q '^SESSION_MODE=' .env 2>/dev/null; then
  run_in_container setup_pxgrid.py first-run
fi

echo ""
echo "Starting ISE agent..."
${COMPOSE_CMD} up -d
echo ""
echo "ISE agent is running. View logs with: ${RUNTIME} logs -f ${CONTAINER_NAME}"
