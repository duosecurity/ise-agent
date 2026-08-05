#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ise-agent-host-tools.XXXXXX")
cleanup() {
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

RELEASE_DIR="${TEST_ROOT}/release"
INSTALL_DIR="${TEST_ROOT}/install"
BOOTSTRAP_DIR="${TEST_ROOT}/bootstrap"
PACKAGE_DIR="${TEST_ROOT}/package"
ROLLBACK_DIR="${TEST_ROOT}/rollback"
BIN_DIR="${TEST_ROOT}/bin"
COMMAND_LOG="${TEST_ROOT}/commands.log"
mkdir -p \
  "${RELEASE_DIR}" \
  "${INSTALL_DIR}/.launcher" \
  "${BOOTSTRAP_DIR}" \
  "${PACKAGE_DIR}/.launcher" \
  "${PACKAGE_DIR}/certs" \
  "${ROLLBACK_DIR}/.launcher" \
  "${BIN_DIR}"

cp "${REPOSITORY_ROOT}/start.sh" "${RELEASE_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${RELEASE_DIR}/agentctl"
cp "${REPOSITORY_ROOT}/docker-compose.yml" "${RELEASE_DIR}/docker-compose.yml"
(
  cd "${RELEASE_DIR}"
  if command -v sha256sum &>/dev/null; then
    sha256sum start.sh agentctl docker-compose.yml > SHA256SUMS
  else
    shasum -a 256 start.sh agentctl docker-compose.yml > SHA256SUMS
  fi
)

cat > "${BIN_DIR}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${ISE_AGENT_TEST_COMMAND_LOG}"
if [[ "${1:-}" == "compose" ]] && [[ "${2:-}" == "version" ]]; then
  exit 0
fi
if [[ -n "${ISE_AGENT_TEST_FAIL_UP_ONCE:-}" ]] \
  && [[ "$*" == "compose up -d" ]] \
  && [[ ! -f "${ISE_AGENT_TEST_FAIL_UP_ONCE}" ]]; then
  touch "${ISE_AGENT_TEST_FAIL_UP_ONCE}"
  exit 1
fi
exit 0
EOF
chmod +x "${BIN_DIR}/docker"

cp "${REPOSITORY_ROOT}/start.sh" "${INSTALL_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${INSTALL_DIR}/.launcher/agentctl"
cp "${REPOSITORY_ROOT}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/.launcher/agentctl"
cat > "${INSTALL_DIR}/.env" <<'EOF'
AGENT_ID=test-tenant__ISE__12345678-abcd
EOF

PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_RELEASE_ASSET_BASE="file://${RELEASE_DIR}" \
  "${INSTALL_DIR}/start.sh" --update

test -x "${INSTALL_DIR}/.launcher/agentctl"
test -f "${INSTALL_DIR}/.launcher/previous/start.sh"
test -f "${INSTALL_DIR}/.launcher/previous/agentctl"
test -f "${INSTALL_DIR}/.launcher/previous/docker-compose.yml"
test ! -d "${INSTALL_DIR}/.launcher/update.lock"
! grep -q '__AGENT_SUFFIX__\|__CONTAINER_NAME__' "${INSTALL_DIR}/docker-compose.yml"
grep -q 'pull ghcr.io/duosecurity/ise-agent:latest' "${COMMAND_LOG}"
grep -q 'compose .*config --quiet' "${COMMAND_LOG}"
grep -q 'compose down' "${COMMAND_LOG}"
grep -q 'compose up -d' "${COMMAND_LOG}"

cp "${REPOSITORY_ROOT}/start.sh" "${BOOTSTRAP_DIR}/start.sh"
chmod +x "${BOOTSTRAP_DIR}/start.sh"
PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_RELEASE_ASSET_BASE="file://${RELEASE_DIR}" \
  "${BOOTSTRAP_DIR}/start.sh" --stop

test -x "${BOOTSTRAP_DIR}/.launcher/agentctl"

cp "${REPOSITORY_ROOT}/start.sh" "${PACKAGE_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${PACKAGE_DIR}/.launcher/agentctl"
cp "${REPOSITORY_ROOT}/docker-compose.yml" "${PACKAGE_DIR}/docker-compose.yml"
chmod +x "${PACKAGE_DIR}/start.sh" "${PACKAGE_DIR}/.launcher/agentctl"
cat > "${PACKAGE_DIR}/.env" <<'EOF'
AGENT_ID=test-tenant__ISE__12345678-abcd
EOF
printf '%s\n' 'https://api.example.test/ise-agent/bootstrap' > "${PACKAGE_DIR}/certs/certificate.pem.crt"
printf '%s\n' 'iseb1.token.secret' > "${PACKAGE_DIR}/certs/private.pem.key"
touch "${PACKAGE_DIR}/certs/.credentials.enc" "${PACKAGE_DIR}/certs/.pxgrid.enc"
PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
  "${PACKAGE_DIR}/start.sh" --no-pull

grep -q '/app/bootstrap_iot.py --packaged --output-dir /bootstrap' "${COMMAND_LOG}"

cp "${REPOSITORY_ROOT}/start.sh" "${ROLLBACK_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${ROLLBACK_DIR}/.launcher/agentctl"
cp "${REPOSITORY_ROOT}/docker-compose.yml" "${ROLLBACK_DIR}/docker-compose.yml"
printf '\n# previous-start\n' >> "${ROLLBACK_DIR}/start.sh"
printf '\n# previous-controller\n' >> "${ROLLBACK_DIR}/.launcher/agentctl"
printf '\n# previous-compose\n' >> "${ROLLBACK_DIR}/docker-compose.yml"
chmod +x "${ROLLBACK_DIR}/start.sh" "${ROLLBACK_DIR}/.launcher/agentctl"
cat > "${ROLLBACK_DIR}/.env" <<'EOF'
AGENT_ID=test-tenant__ISE__12345678-abcd
EOF

if PATH="${BIN_DIR}:${PATH}" \
  ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
  ISE_AGENT_TEST_FAIL_UP_ONCE="${TEST_ROOT}/failed-up" \
  ISE_AGENT_RELEASE_ASSET_BASE="file://${RELEASE_DIR}" \
    "${ROLLBACK_DIR}/start.sh" --update; then
  echo "Expected the failed restart to return a failure." >&2
  exit 1
fi

grep -q '# previous-start' "${ROLLBACK_DIR}/start.sh"
grep -q '# previous-controller' "${ROLLBACK_DIR}/.launcher/agentctl"
grep -q '# previous-compose' "${ROLLBACK_DIR}/docker-compose.yml"

echo "Host-tool update tests passed."
