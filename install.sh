#!/usr/bin/env bash
set -euo pipefail

RELEASE_ASSET_BASE="${ISE_AGENT_RELEASE_ASSET_BASE:-https://github.com/duosecurity/ise-agent/releases/latest/download}"

# Bundle: base64(iotEndpoint)|base64(tenantId)|base64(agentId)|base64(mqttTopicPrefix)|base64(cert)|base64(key)
BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
  echo "Usage: cd <install-dir> && curl -fsSL <url>/install.sh | bash -s \"<bundle>\"" >&2
  exit 1
fi

decode_field() {
  echo "$BUNDLE" | cut -d'|' -f"$1" | base64 --decode
}

IOT_ENDPOINT=$(decode_field 1)
TENANT_ID=$(decode_field 2)
AGENT_ID=$(decode_field 3)
MQTT_TOPIC_PREFIX=$(decode_field 4)
CERT=$(decode_field 5)
PRIVATE_KEY=$(decode_field 6)

# Derive per-agent suffix (matches container name and ZIP package naming)
AGENT_SUFFIX=$(echo "$AGENT_ID" | awk -F'__' '{print $NF}' | cut -c1-8)
CONTAINER_NAME="ise-agent-${AGENT_SUFFIX}"
INSTALL_DIR="$(pwd)"

echo "Installing ISE agent in ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/certs"

# Write .env
cat > "${INSTALL_DIR}/.env" <<EOF
IOT_ENDPOINT=${IOT_ENDPOINT}
TENANT_ID=${TENANT_ID}
AGENT_ID=${AGENT_ID}
MQTT_TOPIC_PREFIX=${MQTT_TOPIC_PREFIX}
EOF

# Write certs
printf '%s' "$CERT" > "${INSTALL_DIR}/certs/certificate.pem.crt"
printf '%s' "$PRIVATE_KEY" > "${INSTALL_DIR}/certs/private.pem.key"
chmod 600 "${INSTALL_DIR}/certs/"*

# Download the versioned host tools from the latest published release
mkdir -p "${INSTALL_DIR}/.launcher"
curl -fsSL "${RELEASE_ASSET_BASE}/SHA256SUMS" -o "${INSTALL_DIR}/.launcher/SHA256SUMS"
curl -fsSL "${RELEASE_ASSET_BASE}/docker-compose.yml" -o "${INSTALL_DIR}/.launcher/docker-compose.yml.template"
curl -fsSL "${RELEASE_ASSET_BASE}/start.sh" -o "${INSTALL_DIR}/start.sh"
curl -fsSL "${RELEASE_ASSET_BASE}/agentctl" -o "${INSTALL_DIR}/.launcher/agentctl"

verify_asset() {
  local name="$1"
  local path="$2"
  local expected actual
  expected=$(awk -v name="${name}" '$2 == name {print $1}' "${INSTALL_DIR}/.launcher/SHA256SUMS")
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

verify_asset start.sh "${INSTALL_DIR}/start.sh"
verify_asset agentctl "${INSTALL_DIR}/.launcher/agentctl"
verify_asset docker-compose.yml "${INSTALL_DIR}/.launcher/docker-compose.yml.template"
bash -n "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/.launcher/agentctl"
sed "s|__CONTAINER_NAME__|${CONTAINER_NAME}|g; s|__AGENT_SUFFIX__|${AGENT_SUFFIX}|g" \
  "${INSTALL_DIR}/.launcher/docker-compose.yml.template" > "${INSTALL_DIR}/docker-compose.yml"
chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/.launcher/agentctl"
rm -f "${INSTALL_DIR}/.launcher/SHA256SUMS" "${INSTALL_DIR}/.launcher/docker-compose.yml.template"

echo ""
echo "Installation complete. Starting ISE agent..."
echo ""

# Re-attach to terminal so start.sh can prompt for ISE credentials interactively
exec "${INSTALL_DIR}/start.sh" < /dev/tty
