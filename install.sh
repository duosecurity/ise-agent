#!/usr/bin/env bash
set -euo pipefail

RELEASE_ASSET_BASE="${ISE_AGENT_RELEASE_ASSET_BASE:-https://github.com/duosecurity/ise-agent/releases/latest/download}"
IMAGE="ghcr.io/duosecurity/ise-agent:latest"

BUNDLE="${1:-}"
set --

if [[ -z "${BUNDLE}" ]]; then
  echo "Usage: cd <install-dir> && curl -fsSL <url>/install.sh | bash -s \"<bundle>\"" >&2
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

set_container_user_mode() {
  local runtime_info
  RUN_AS_HOST_USER=1

  # Rootless runtimes map container root to the caller. Forcing the caller's
  # numeric UID instead maps to a subordinate UID that cannot write this mount.
  if [[ "${RUNTIME}" == "podman" ]]; then
    if ! runtime_info=$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null); then
      echo "Error: unable to determine whether Podman is running rootless." >&2
      exit 1
    fi
    if [[ "${runtime_info}" == "true" ]]; then
      RUN_AS_HOST_USER=0
      return
    fi
  elif [[ "${RUNTIME}" == "docker" ]]; then
    if ! runtime_info=$(docker info --format '{{json .SecurityOptions}}' 2>/dev/null); then
      echo "Error: unable to determine whether Docker is running rootless." >&2
      exit 1
    fi
    if [[ "${runtime_info}" == *rootless* ]]; then
      RUN_AS_HOST_USER=0
      return
    fi
  fi
}

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
  "${INSTALL_DIR}/.launcher/agentctl" \
  "${INSTALL_DIR}/certs/certificate.pem.crt" \
  "${INSTALL_DIR}/certs/private.pem.key"; do
  if [[ -e "${target}" ]]; then
    echo "Error: refusing to overwrite existing agent configuration at ${target}." >&2
    exit 1
  fi
done

echo "Downloading the current ISE agent launcher..."
curl -fsSL "${RELEASE_ASSET_BASE}/SHA256SUMS" -o "${TEMP_DIR}/SHA256SUMS"
curl -fsSL "${RELEASE_ASSET_BASE}/docker-compose.yml" -o "${TEMP_DIR}/docker-compose.yml.template"
curl -fsSL "${RELEASE_ASSET_BASE}/start.sh" -o "${TEMP_DIR}/start.sh"
curl -fsSL "${RELEASE_ASSET_BASE}/agentctl" -o "${TEMP_DIR}/agentctl"

verify_asset() {
  local name="$1"
  local path="$2"
  local expected actual
  expected=$(awk -v name="${name}" '$2 == name {print $1}' "${TEMP_DIR}/SHA256SUMS")
  if command -v sha256sum &>/dev/null; then
    actual=$(sha256sum "${path}" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    actual=$(shasum -a 256 "${path}" | awk '{print $1}')
  else
    echo "Error: sha256sum or shasum is required to verify the installer download." >&2
    exit 1
  fi
  if [[ ! "${expected}" =~ ^[0-9a-fA-F]{64}$ ]] || [[ "${actual}" != "${expected}" ]]; then
    echo "Error: checksum verification failed for ${name}." >&2
    exit 1
  fi
}

verify_asset start.sh "${TEMP_DIR}/start.sh"
verify_asset agentctl "${TEMP_DIR}/agentctl"
verify_asset docker-compose.yml "${TEMP_DIR}/docker-compose.yml.template"
bash -n "${TEMP_DIR}/start.sh" "${TEMP_DIR}/agentctl"

echo "Pulling the ISE agent image..."
"${RUNTIME}" pull "${IMAGE}"

echo "Installing the ISE agent credential bundle inside the container..."
set_container_user_mode
bootstrap_cmd=("${RUNTIME}" run --rm --pull=never -i)
if [[ "${RUN_AS_HOST_USER}" == "1" ]]; then
  bootstrap_cmd+=(--user "$(id -u):$(id -g)")
fi
bootstrap_cmd+=(
  -v "${INSTALL_DIR}:/bootstrap"
  --entrypoint python "${IMAGE}" -u /app/bootstrap_iot.py
  --bundle
  --output-dir /bootstrap
)
printf '%s' "${BUNDLE}" | "${bootstrap_cmd[@]}"
BUNDLE=""

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
mkdir -p "${INSTALL_DIR}/.launcher"
mv "${TEMP_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
mv "${TEMP_DIR}/start.sh" "${INSTALL_DIR}/start.sh"
mv "${TEMP_DIR}/agentctl" "${INSTALL_DIR}/.launcher/agentctl"
chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/.launcher/agentctl"

echo ""
echo "Installation complete. Starting ISE agent..."
echo ""

cleanup
trap - EXIT

# Re-attach to terminal so start.sh can prompt for ISE credentials interactively
exec "${INSTALL_DIR}/start.sh" --no-pull < /dev/tty
