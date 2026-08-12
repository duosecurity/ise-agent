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
UNCHANGED_DIR="${TEST_ROOT}/unchanged"
AUTO_UPDATE_DIR="${TEST_ROOT}/auto-update"
BIN_DIR="${TEST_ROOT}/bin"
COMMAND_LOG="${TEST_ROOT}/commands.log"
CRONTAB_FILE="${TEST_ROOT}/crontab"
IMAGE_ID_FILE="${TEST_ROOT}/image-id"
PULLED_IMAGE_ID_FILE="${TEST_ROOT}/pulled-image-id"
mkdir -p \
  "${RELEASE_DIR}" \
  "${INSTALL_DIR}/.launcher" \
  "${BOOTSTRAP_DIR}" \
  "${PACKAGE_DIR}/.launcher" \
  "${PACKAGE_DIR}/certs" \
  "${ROLLBACK_DIR}/.launcher" \
  "${ROLLBACK_DIR}/certs" \
  "${UNCHANGED_DIR}/.launcher" \
  "${UNCHANGED_DIR}/certs" \
  "${AUTO_UPDATE_DIR}/.launcher" \
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
if [[ "${1:-}" == "image" ]] && [[ "${2:-}" == "inspect" ]]; then
  cat "${ISE_AGENT_TEST_IMAGE_ID_FILE}"
  exit 0
fi
if [[ "${1:-}" == "image" ]] && [[ "${2:-}" == "tag" ]]; then
  printf '%s\n' "${3}" > "${ISE_AGENT_TEST_IMAGE_ID_FILE}"
  exit 0
fi
if [[ "${1:-}" == "pull" ]]; then
  cat "${ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE}" > "${ISE_AGENT_TEST_IMAGE_ID_FILE}"
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

cat > "${BIN_DIR}/crontab" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-l" ]]; then
  [[ -f "${ISE_AGENT_TEST_CRONTAB_FILE}" ]] && cat "${ISE_AGENT_TEST_CRONTAB_FILE}"
  exit 0
fi
cp "$1" "${ISE_AGENT_TEST_CRONTAB_FILE}"
EOF
chmod +x "${BIN_DIR}/crontab"

printf '%s\n' old-image > "${IMAGE_ID_FILE}"
printf '%s\n' new-image > "${PULLED_IMAGE_ID_FILE}"

cp "${REPOSITORY_ROOT}/start.sh" "${INSTALL_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${INSTALL_DIR}/.launcher/agentctl"
cp "${REPOSITORY_ROOT}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
chmod +x "${INSTALL_DIR}/start.sh" "${INSTALL_DIR}/.launcher/agentctl"
cat > "${INSTALL_DIR}/.env" <<'EOF'
AGENT_ID=test-tenant__ISE__12345678-abcd
EOF

PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_TEST_IMAGE_ID_FILE="${IMAGE_ID_FILE}" \
ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE="${PULLED_IMAGE_ID_FILE}" \
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
ISE_AGENT_TEST_IMAGE_ID_FILE="${IMAGE_ID_FILE}" \
ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE="${PULLED_IMAGE_ID_FILE}" \
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
ISE_AGENT_TEST_IMAGE_ID_FILE="${IMAGE_ID_FILE}" \
ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE="${PULLED_IMAGE_ID_FILE}" \
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
printf '%s\n' checkpoint > "${ROLLBACK_DIR}/certs/.sync-state.json"
printf '%s\n' old-image > "${IMAGE_ID_FILE}"
printf '%s\n' new-image > "${PULLED_IMAGE_ID_FILE}"

if PATH="${BIN_DIR}:${PATH}" \
  ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
  ISE_AGENT_TEST_IMAGE_ID_FILE="${IMAGE_ID_FILE}" \
  ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE="${PULLED_IMAGE_ID_FILE}" \
  ISE_AGENT_TEST_FAIL_UP_ONCE="${TEST_ROOT}/failed-up" \
  ISE_AGENT_RELEASE_ASSET_BASE="file://${RELEASE_DIR}" \
    "${ROLLBACK_DIR}/start.sh" --update; then
  echo "Expected the failed restart to return a failure." >&2
  exit 1
fi

grep -q '# previous-start' "${ROLLBACK_DIR}/start.sh"
grep -q '# previous-controller' "${ROLLBACK_DIR}/.launcher/agentctl"
grep -q '# previous-compose' "${ROLLBACK_DIR}/docker-compose.yml"
grep -q 'old-image' "${IMAGE_ID_FILE}"

cp "${REPOSITORY_ROOT}/start.sh" "${UNCHANGED_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${UNCHANGED_DIR}/.launcher/agentctl"
sed 's|__CONTAINER_NAME__|ise-agent-12345678|g; s|__AGENT_SUFFIX__|12345678|g' \
  "${REPOSITORY_ROOT}/docker-compose.yml" > "${UNCHANGED_DIR}/docker-compose.yml"
chmod +x "${UNCHANGED_DIR}/start.sh" "${UNCHANGED_DIR}/.launcher/agentctl"
cat > "${UNCHANGED_DIR}/.env" <<'EOF'
AGENT_ID=test-tenant__ISE__12345678-abcd
EOF
printf '%s\n' current-image > "${IMAGE_ID_FILE}"
printf '%s\n' current-image > "${PULLED_IMAGE_ID_FILE}"
: > "${COMMAND_LOG}"
PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_TEST_IMAGE_ID_FILE="${IMAGE_ID_FILE}" \
ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE="${PULLED_IMAGE_ID_FILE}" \
ISE_AGENT_RELEASE_ASSET_BASE="file://${RELEASE_DIR}" \
  "${UNCHANGED_DIR}/start.sh" --update

if grep -q 'compose down\|compose up -d' "${COMMAND_LOG}"; then
  echo "Expected an unchanged update to skip the restart." >&2
  exit 1
fi

printf '%s\n' checkpoint > "${UNCHANGED_DIR}/certs/.sync-state.json"
: > "${COMMAND_LOG}"
PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_TEST_IMAGE_ID_FILE="${IMAGE_ID_FILE}" \
ISE_AGENT_TEST_PULLED_IMAGE_ID_FILE="${PULLED_IMAGE_ID_FILE}" \
ISE_AGENT_RELEASE_ASSET_BASE="file://${RELEASE_DIR}" \
  "${UNCHANGED_DIR}/start.sh" --update --full-resync

test ! -e "${UNCHANGED_DIR}/certs/.sync-state.json"
grep -q 'compose up -d' "${COMMAND_LOG}"

cp "${REPOSITORY_ROOT}/start.sh" "${AUTO_UPDATE_DIR}/start.sh"
cp "${REPOSITORY_ROOT}/agentctl" "${AUTO_UPDATE_DIR}/.launcher/agentctl"
cp "${REPOSITORY_ROOT}/docker-compose.yml" "${AUTO_UPDATE_DIR}/docker-compose.yml"
chmod +x "${AUTO_UPDATE_DIR}/start.sh" "${AUTO_UPDATE_DIR}/.launcher/agentctl"
cat > "${AUTO_UPDATE_DIR}/.env" <<'EOF'
AGENT_ID=test-tenant__ISE__12345678-abcd
EOF
PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_TEST_CRONTAB_FILE="${CRONTAB_FILE}" \
  "${AUTO_UPDATE_DIR}/start.sh" --enable-auto-update

grep -q 'BEGIN CII ISE Agent automatic update:' "${CRONTAB_FILE}"
grep -q '/.launcher/auto-update.sh' "${CRONTAB_FILE}"
grep -q 'exec ./start.sh --update' "${AUTO_UPDATE_DIR}/.launcher/auto-update.sh"

PATH="${BIN_DIR}:${PATH}" \
ISE_AGENT_TEST_COMMAND_LOG="${COMMAND_LOG}" \
ISE_AGENT_TEST_CRONTAB_FILE="${CRONTAB_FILE}" \
  "${AUTO_UPDATE_DIR}/start.sh" --disable-auto-update

if grep -q 'CII ISE Agent automatic update:' "${CRONTAB_FILE}"; then
  echo "Expected automatic update cron entry to be removed." >&2
  exit 1
fi
test ! -e "${AUTO_UPDATE_DIR}/.launcher/auto-update.sh"

echo "Host-tool update tests passed."
