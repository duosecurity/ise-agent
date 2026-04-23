#!/usr/bin/env bash
#
# ISE Agent start script.
#
# On first run, prompts for ISE credentials and encrypts them locally.
# Then starts the agent via docker/podman compose.
#
# Usage:
#   ./start.sh                  # Normal start (prompts on first run)
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

IMAGE="ghcr.io/duosecurity/ise-agent:latest"
CONTAINER_NAME=$(grep 'container_name:' docker-compose.yml | head -1 | awk '{print $2}' 2>/dev/null || echo "ise-agent")

# -- Helpers --

check_prerequisites() {
  if [[ -z "${RUNTIME}" ]]; then
    echo "Error: No container runtime found." >&2
    echo "Install one of: docker or podman." >&2
    exit 1
  fi

  if [[ ! -f "${KEY_FILE}" ]]; then
    echo "Error: IoT private key not found at ${KEY_FILE}" >&2
    echo "Make sure you've extracted the full agent package." >&2
    exit 1
  fi

  if [[ ! -f "${CERT_FILE}" ]]; then
    echo "Error: IoT certificate not found at ${CERT_FILE}" >&2
    exit 1
  fi

  if [[ ! -f ".env" ]]; then
    echo "Error: .env file not found." >&2
    echo "Make sure you've extracted the full agent package." >&2
    exit 1
  fi
}

prompt_credentials() {
  echo ""
  echo "Running ISE credential setup inside container..."
  TTY_FLAG=$([ -t 0 ] && echo "-t" || echo "")
  ${RUNTIME} run --rm -i ${TTY_FLAG} -v "$(pwd)/certs:/app/certs" --entrypoint python "${IMAGE}" -u /app/setup_credentials.py
}

enable_pxgrid_in_env() {
  local node="$1"
  # Password is encrypted at rest in ./certs/.pxgrid.enc — only node name lives in .env
  sed -i.bak '/^SESSION_MODE=/d; /^PXGRID_NODE_NAME=/d; /^PXGRID_PASSWORD=/d' .env
  rm -f .env.bak
  cat >> .env <<EOF

# pxGrid real-time session monitoring
SESSION_MODE=pxgrid
PXGRID_NODE_NAME=${node}
EOF
}

disable_pxgrid_in_env() {
  sed -i.bak '/^SESSION_MODE=/d; /^PXGRID_NODE_NAME=/d; /^PXGRID_PASSWORD=/d' .env
  rm -f .env.bak
  # Remove the encrypted password too so a future re-enable re-registers cleanly
  rm -f ./certs/.pxgrid.enc
}

prompt_enable_pxgrid() {
  echo ""
  echo "=== Session monitoring mode ==="
  echo ""
  echo "The agent can monitor ISE sessions two ways:"
  echo "  - pxGrid (recommended): real-time session events via WebSocket"
  echo "  - MnT polling: periodic REST polling (slower, higher ISE load)"
  echo ""
  read -rp "Enable pxGrid real-time session monitoring? [Y/n]: " ENABLE_PX
  ENABLE_PX="${ENABLE_PX:-Y}"
  if [[ "${ENABLE_PX}" =~ ^[Yy]$ ]]; then
    read -rp "  pxGrid Node Name [cii-agent]: " PXGRID_NODE
    PXGRID_NODE="${PXGRID_NODE:-cii-agent}"
    enable_pxgrid_in_env "${PXGRID_NODE}"
    echo ""
    echo "pxGrid enabled. On first start the agent will register itself with ISE."
    echo "Ask your ISE admin to approve the '${PXGRID_NODE}' client in"
    echo "Administration > pxGrid Services > Client Management > Clients."
  else
    disable_pxgrid_in_env
    echo ""
    echo "pxGrid disabled. The agent will poll ISE MnT for sessions."
    echo "You can switch later with: ./start.sh --enable-pxgrid"
  fi
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

if [[ "${ACTION}" == "enable-pxgrid" ]]; then
  echo ""
  echo "=== Enable pxGrid Real-Time Session Monitoring ==="
  echo ""
  echo "This upgrades session monitoring from polling to real-time via ISE pxGrid 2.0."
  echo "The agent will register itself with ISE and wait for your admin to approve it."
  echo ""
  read -rp "  pxGrid Node Name [cii-agent]: " PXGRID_NODE
  PXGRID_NODE="${PXGRID_NODE:-cii-agent}"
  enable_pxgrid_in_env "${PXGRID_NODE}"
  echo ""
  echo "pxGrid enabled. Restarting agent..."
  ${COMPOSE_CMD} down 2>/dev/null || true
  ${COMPOSE_CMD} up -d
  echo ""
  echo "Agent restarted. It will register itself with ISE and wait for admin approval."
  echo "Check logs: ${RUNTIME} logs -f ${CONTAINER_NAME}"
  echo ""
  echo "Next steps:"
  echo "  1. Ask your ISE admin to approve the '${PXGRID_NODE}' client in"
  echo "     Administration > pxGrid Services > Client Management > Clients"
  echo "  2. Once approved, the agent will subscribe automatically"
  exit 0
fi

if [[ "${ACTION}" == "disable-pxgrid" ]]; then
  disable_pxgrid_in_env
  echo "pxGrid disabled. Restarting agent with MnT polling..."
  ${COMPOSE_CMD} down 2>/dev/null || true
  ${COMPOSE_CMD} up -d
  echo "Done. View logs: ${RUNTIME} logs -f ${CONTAINER_NAME}"
  exit 0
fi

check_prerequisites

echo "Using: ${COMPOSE_CMD}"

FIRST_RUN=0
if [[ "${ACTION}" == "reconfigure" ]] || [[ ! -f "${CREDENTIALS_FILE}" ]]; then
  [[ ! -f "${CREDENTIALS_FILE}" ]] && FIRST_RUN=1
  prompt_credentials
fi

# On first run, ask whether to enable pxGrid. Skip if .env already has a SESSION_MODE set.
if [[ "${FIRST_RUN}" == "1" ]] && ! grep -q '^SESSION_MODE=' .env 2>/dev/null; then
  prompt_enable_pxgrid
fi

echo ""
echo "Starting ISE agent..."
${COMPOSE_CMD} up -d

echo ""
echo "ISE agent is running. View logs with: ${RUNTIME} logs -f ${CONTAINER_NAME}"
