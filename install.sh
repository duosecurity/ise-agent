#!/usr/bin/env bash
set -euo pipefail

RELEASE_ASSET_BASE="https://github.com/duosecurity/ise-agent/releases/latest/download"
IMAGE="ghcr.io/duosecurity/ise-agent:latest"

BOOTSTRAP_ENDPOINT="${1:-}"
BOOTSTRAP_TOKEN="${2:-}"
set --

if [[ -z "${BOOTSTRAP_ENDPOINT}" || -z "${BOOTSTRAP_TOKEN}" ]]; then
  echo "Usage: cd <install-dir> && curl -fsSL <url>/install.sh | bash -s -- <bootstrap-endpoint> <bootstrap-token>" >&2
  exit 1
fi

detect_runtime() {
  if command -v docker &>/dev/null; then
    echo "docker"
  elif command -v podman &>/dev/null; then
    echo "podman"
  else
    echo ""
  fi
}

RUNTIME="$(detect_runtime)"
if [[ -z "${RUNTIME}" ]]; then
  echo "Error: Docker or Podman is required to install the ISE agent." >&2
  exit 1
fi
HOST_USER="$(id -u):$(id -g)"

INSTALL_DIR="$(pwd -P)"
echo "Installing ISE agent in ${INSTALL_DIR}..."

TEMP_DIR="$(mktemp -d "${INSTALL_DIR}/.ise-agent-install.XXXXXX")"
cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

for target in \
  "${INSTALL_DIR}/.env" \
  "${INSTALL_DIR}/docker-compose.yml" \
  "${INSTALL_DIR}/start.sh" \
  "${INSTALL_DIR}/certs/certificate.pem.crt" \
  "${INSTALL_DIR}/certs/private.pem.key"; do
  if [[ -e "${target}" ]]; then
    echo "Error: refusing to overwrite existing agent configuration at ${target}." >&2
    exit 1
  fi
done

echo "Downloading the current ISE agent launcher..."
curl -fsSL "${RELEASE_ASSET_BASE}/docker-compose.yml" -o "${TEMP_DIR}/docker-compose.yml.template"
curl -fsSL "${RELEASE_ASSET_BASE}/start.sh" -o "${TEMP_DIR}/start.sh"
bash -n "${TEMP_DIR}/start.sh"

echo "Pulling the ISE agent image..."
"${RUNTIME}" pull "${IMAGE}"

echo "Generating the private key locally and requesting its AWS IoT certificate..."
printf '%s' "${BOOTSTRAP_TOKEN}" | "${RUNTIME}" run --rm --pull=never -i \
  --user "${HOST_USER}" \
  -v "${INSTALL_DIR}:/bootstrap" \
  --entrypoint python "${IMAGE}" -u /app/bootstrap_iot.py \
  --endpoint "${BOOTSTRAP_ENDPOINT}" \
  --output-dir /bootstrap
BOOTSTRAP_TOKEN=""

AGENT_ID=$(sed -n 's/^AGENT_ID=//p' "${INSTALL_DIR}/.env")
if [[ ! "${AGENT_ID}" =~ __ISE__[A-Za-z0-9-]+$ ]]; then
  echo "Error: bootstrap did not return an agent ID." >&2
  exit 1
fi

AGENT_SUFFIX="${AGENT_ID##*__}"
AGENT_SUFFIX="${AGENT_SUFFIX:0:8}"
CONTAINER_NAME="ise-agent-${AGENT_SUFFIX}"

sed "s|__CONTAINER_NAME__|${CONTAINER_NAME}|g; s|__AGENT_SUFFIX__|${AGENT_SUFFIX}|g" \
  "${TEMP_DIR}/docker-compose.yml.template" > "${TEMP_DIR}/docker-compose.yml"
mv "${TEMP_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
mv "${TEMP_DIR}/start.sh" "${INSTALL_DIR}/start.sh"
chmod +x "${INSTALL_DIR}/start.sh"

echo ""
echo "Installation complete. Starting ISE agent..."
echo ""

cleanup
trap - EXIT

# Re-attach to terminal so start.sh can prompt for ISE credentials interactively
exec "${INSTALL_DIR}/start.sh" --no-pull < /dev/tty
