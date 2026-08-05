#!/usr/bin/env bash
#
# Stable bootstrap for the versioned ISE Agent host controller.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTROLLER="${SCRIPT_DIR}/.launcher/agentctl"
RELEASE_ASSET_BASE="${ISE_AGENT_RELEASE_ASSET_BASE:-https://github.com/duosecurity/ise-agent/releases/latest/download}"

checksum_file() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "Error: sha256sum or shasum is required to install the ISE agent controller." >&2
    return 1
  fi
}

bootstrap_controller() (
  local staging expected actual
  staging=$(mktemp -d "${SCRIPT_DIR}/.ise-agent-bootstrap.XXXXXX")
  cleanup_bootstrap() {
    rm -rf "${staging}"
  }
  trap cleanup_bootstrap EXIT

  echo "Downloading the ISE agent host controller..."
  curl -fsSL "${RELEASE_ASSET_BASE}/SHA256SUMS" -o "${staging}/SHA256SUMS"
  curl -fsSL "${RELEASE_ASSET_BASE}/agentctl" -o "${staging}/agentctl"
  expected=$(awk '$2 == "agentctl" {print $1}' "${staging}/SHA256SUMS")
  actual=$(checksum_file "${staging}/agentctl")
  if [[ ! "${expected}" =~ ^[0-9a-fA-F]{64}$ ]] || [[ "${actual}" != "${expected}" ]]; then
    echo "Error: ISE agent controller checksum verification failed." >&2
    return 1
  fi
  bash -n "${staging}/agentctl"
  mkdir -p "${SCRIPT_DIR}/.launcher"
  chmod +x "${staging}/agentctl"
  mv "${staging}/agentctl" "${CONTROLLER}"
)

if [[ ! -x "${CONTROLLER}" ]]; then
  bootstrap_controller
fi

exec "${CONTROLLER}" "$@"
