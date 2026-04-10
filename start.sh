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

IMAGE="public.ecr.aws/oort/ise-agent:latest"

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
  ${RUNTIME} run --rm -it -v "$(pwd)/certs:/app/certs" --entrypoint python "${IMAGE}" -u /app/setup_credentials.py
}

# -- Main --

ACTION=""
for arg in "$@"; do
  case "${arg}" in
    --reconfigure) ACTION="reconfigure" ;;
    --stop) ACTION="stop" ;;
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

echo "Using: ${COMPOSE_CMD}"

if [[ "${ACTION}" == "reconfigure" ]] || [[ ! -f "${CREDENTIALS_FILE}" ]]; then
  prompt_credentials
fi

echo ""
echo "Starting ISE agent..."
${COMPOSE_CMD} up -d

echo ""
echo "ISE agent is running. View logs with: ${COMPOSE_CMD} logs -f"
