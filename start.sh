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
#   ./start.sh --update         # Pull the latest image and restart the agent
#   ./start.sh --no-pull        # Skip image pull for offline/local-image environments
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
PULL_IMAGE=1
IMAGE_PULLED=0
ISE_AGENT_NETWORK_MODE="${ISE_AGENT_NETWORK_MODE:-}"

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

load_network_mode() {
  local network_mode="${ISE_AGENT_NETWORK_MODE:-}"

  if [[ -z "${network_mode}" ]] && [[ -r ".env" ]]; then
    network_mode=$(
      # shellcheck disable=SC1091
      source .env
      printf '%s' "${ISE_AGENT_NETWORK_MODE:-}"
    )
  fi

  ISE_AGENT_NETWORK_MODE="${network_mode:-}"
  case "${ISE_AGENT_NETWORK_MODE}" in
    ""|bridge|host)
      ;;
    *)
      echo "Error: ISE_AGENT_NETWORK_MODE must be empty, bridge, or host." >&2
      exit 1
      ;;
  esac

  export ISE_AGENT_NETWORK_MODE
}

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

pull_image_once() {
  if [[ "${PULL_IMAGE}" != "1" ]] || [[ "${IMAGE_PULLED}" == "1" ]]; then
    return
  fi

  echo "Pulling latest ISE agent image..."
  ${RUNTIME} pull "${IMAGE}"
  IMAGE_PULLED=1
}

run_in_container() {
  # Run a one-off container with certs mounted so setup scripts can read/write
  # the encrypted credential stores without the host knowing their layout.
  pull_image_once
  local script="$1"
  shift
  local tty_args=()
  local network_args=()
  [[ -t 0 ]] && tty_args=(-t)
  [[ "${ISE_AGENT_NETWORK_MODE}" == "host" ]] && network_args=(--network host)
  ${RUNTIME} run --rm --pull=never "${network_args[@]}" -i "${tty_args[@]}" \
    --env-file "$(pwd)/.env" \
    -v "$(pwd)/certs:/app/certs" \
    --entrypoint python "${IMAGE}" -u "/app/${script}" "$@"
}

compose_restart() {
  compose_cmd down 2>/dev/null || true
  compose_cmd up -d
  echo "View logs: ${RUNTIME} logs -f ${CONTAINER_NAME}"
}

compose_cmd() {
  ${COMPOSE_CMD} "$@"
}

# -- Main --

ACTION=""
for arg in "$@"; do
  case "${arg}" in
    --reconfigure) ACTION="reconfigure" ;;
    --stop) ACTION="stop" ;;
    --update) ACTION="update" ;;
    --enable-pxgrid) ACTION="enable-pxgrid" ;;
    --disable-pxgrid) ACTION="disable-pxgrid" ;;
    --no-pull) PULL_IMAGE=0 ;;
    *) echo "Unknown option: ${arg}" >&2; exit 1 ;;
  esac
done

if [[ -z "${COMPOSE_CMD}" ]]; then
  echo "Error: No container runtime found. Install docker or podman." >&2
  exit 1
fi

load_network_mode

if [[ "${ACTION}" == "stop" ]]; then
  echo "Stopping ISE agent..."
  compose_cmd down
  exit 0
fi

if [[ "${ACTION}" == "update" ]]; then
  if [[ "${PULL_IMAGE}" != "1" ]]; then
    echo "Skipping image pull (--no-pull). Restarting with local image."
  fi
  pull_image_once
  compose_restart
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

# On first run only (no pxGrid state yet), ask whether to enable pxGrid.
if [[ "${FIRST_RUN}" == "1" ]] && [[ ! -f "./certs/.pxgrid.enc" ]]; then
  run_in_container setup_pxgrid.py first-run
fi

echo ""
echo "Starting ISE agent..."
pull_image_once
compose_cmd up -d
echo ""
echo "ISE agent is running. View logs with: ${RUNTIME} logs -f ${CONTAINER_NAME}"
