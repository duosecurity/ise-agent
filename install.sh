#!/usr/bin/env bash
set -euo pipefail

RELEASE_ASSET_BASE="https://github.com/duosecurity/ise-agent/releases/latest/download"

INSTALL_DIR="$(pwd)"

echo "Installing ISE agent in ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/certs"
touch "${INSTALL_DIR}/.env"
chmod 600 "${INSTALL_DIR}/.env"

# Download docker-compose.yml and start.sh from the latest published release
curl -fsSL "${RELEASE_ASSET_BASE}/docker-compose.yml" -o "${INSTALL_DIR}/docker-compose.yml"

curl -fsSL "${RELEASE_ASSET_BASE}/start.sh" -o "${INSTALL_DIR}/start.sh"
chmod +x "${INSTALL_DIR}/start.sh"

echo ""
echo "Installation complete. Starting ISE agent..."
echo ""

# Re-attach to terminal so start.sh can prompt for ISE credentials interactively
exec "${INSTALL_DIR}/start.sh" < /dev/tty
