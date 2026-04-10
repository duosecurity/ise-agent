#!/usr/bin/env bash
set -euo pipefail

GITHUB_RAW_BASE="https://raw.githubusercontent.com/duosecurity/ise-agent/v0.1"

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

# Intervals (seconds)
HEARTBEAT_INTERVAL=60
SESSION_INTERVAL=120
DIRECTORY_INTERVAL=900
EOF

# Write certs
printf '%s' "$CERT" > "${INSTALL_DIR}/certs/certificate.pem.crt"
printf '%s' "$PRIVATE_KEY" > "${INSTALL_DIR}/certs/private.pem.key"
chmod 600 "${INSTALL_DIR}/certs/"*

# Download docker-compose.yml and start.sh from GitHub
curl -fsSL "${GITHUB_RAW_BASE}/docker-compose.yml" \
  | sed "s/__CONTAINER_NAME__/${CONTAINER_NAME}/g; s/__AGENT_SUFFIX__/${AGENT_SUFFIX}/g" \
  > "${INSTALL_DIR}/docker-compose.yml"

curl -fsSL "${GITHUB_RAW_BASE}/start.sh" -o "${INSTALL_DIR}/start.sh"
chmod +x "${INSTALL_DIR}/start.sh"

echo ""
echo "Installation complete. Starting ISE agent..."
echo ""

# Re-attach to terminal so start.sh can prompt for ISE credentials interactively
exec "${INSTALL_DIR}/start.sh" < /dev/tty
