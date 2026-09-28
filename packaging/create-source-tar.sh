#!/usr/bin/env bash

# Create the reproducible source archive consumed by ISE-AGENT-INFRA.
# This script is packaging-only; it must not modify the source tree.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: create-source-tar.sh --output-dir DIR --version VERSION [--source-root DIR]

Creates DIR/ise-agent-container-npavar-VERSION.tar.gz and its verification
metadata. The source tree is read-only input; all generated files go to DIR.
EOF
}

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
OUTPUT_DIR=""
SOURCE_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-root)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SOURCE_ROOT="$(cd "$2" && pwd -P)"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      SOURCE_VERSION="$2"
      shift 2
      ;;
    --help|-h)
      usage >&2
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${OUTPUT_DIR}" || -z "${SOURCE_VERSION}" ]]; then
  echo "Error: --output-dir and --version are required." >&2
  usage
  exit 2
fi

[[ -d "${SOURCE_ROOT}/ise-agent" ]] || { echo "Error: missing ise-agent/" >&2; exit 1; }
[[ -d "${SOURCE_ROOT}/ise-agent-container" ]] || { echo "Error: missing ise-agent-container/" >&2; exit 1; }
[[ -f "${SOURCE_ROOT}/ise-agent/start.sh" ]] || { echo "Error: missing ise-agent/start.sh" >&2; exit 1; }
[[ -f "${SOURCE_ROOT}/ise-agent/agentctl" ]] || { echo "Error: missing ise-agent/agentctl" >&2; exit 1; }

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd -P)"

if ! command -v tar >/dev/null 2>&1 || ! command -v gzip >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  echo "Error: tar, gzip, and sha256sum are required." >&2
  exit 1
fi

if command -v rg >/dev/null 2>&1; then
  SECRET_MATCHES=$(rg -l --hidden --no-messages \
    --glob '!**/.git/**' \
    --glob '!**/.venv/**' \
    --glob '!**/__pycache__/**' \
    --glob '!**/.ruff_cache/**' \
    --glob '!**/.claude/**' \
    --glob '!**/.env' \
    --glob '!**/*.pem' \
    --glob '!**/*.key' \
    --glob '!**/*.p12' \
    --glob '!**/*.pfx' \
    'BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY' \
    "${SOURCE_ROOT}" || true)
  if [[ -n "${SECRET_MATCHES}" ]]; then
    echo "Error: private-key material detected in source files:" >&2
    echo "${SECRET_MATCHES}" >&2
    exit 1
  fi
fi

ARCHIVE_BASE="ise-agent-container-npavar-${SOURCE_VERSION}"
ARCHIVE="${OUTPUT_DIR}/${ARCHIVE_BASE}.tar.gz"
CHECKSUMS="${OUTPUT_DIR}/SHA256SUMS"
MANIFEST="${OUTPUT_DIR}/${ARCHIVE_BASE}.manifest"
METADATA="${OUTPUT_DIR}/${ARCHIVE_BASE}.metadata"
TMP_DIR="$(mktemp -d "${OUTPUT_DIR}/.source-tar.XXXXXX")"
TMP_TAR="${TMP_DIR}/${ARCHIVE_BASE}.tar"
TMP_STAGE="${TMP_DIR}/${ARCHIVE_BASE}"
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

mkdir -p "${TMP_STAGE}"

# Copy only the source directories. Exclusions intentionally keep generated
# environments, repository metadata, and customer material out of the bundle.
tar -cf - \
  --exclude='.git' --exclude='*/.git' \
  --exclude='.venv' --exclude='*/.venv' \
  --exclude='__pycache__' --exclude='*/__pycache__' \
  --exclude='.ruff_cache' --exclude='*/.ruff_cache' \
  --exclude='.claude' --exclude='*/.claude' \
  --exclude='.env' --exclude='*/.env' \
  --exclude='*.pyc' --exclude='*.pem' --exclude='*.key' \
  --exclude='*.p12' --exclude='*.pfx' \
  -C "${SOURCE_ROOT}" ise-agent ise-agent-container \
  | tar -xf - -C "${TMP_STAGE}"

# Normalize archive metadata while retaining executable shell tools.
find "${TMP_STAGE}" -type d -exec chmod 0755 {} +
find "${TMP_STAGE}" -type f -exec chmod 0644 {} +
find "${TMP_STAGE}" -type f -name '*.sh' -exec chmod 0755 {} +
chmod 0755 "${TMP_STAGE}/ise-agent/start.sh" "${TMP_STAGE}/ise-agent/agentctl"

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  -cf "${TMP_TAR}" -C "${TMP_STAGE}/.." "${ARCHIVE_BASE}"
gzip -n -c "${TMP_TAR}" > "${ARCHIVE}"

sha256sum "${ARCHIVE}" > "${CHECKSUMS}"
tar -tzf "${ARCHIVE}" | sort > "${MANIFEST}"

{
  echo "ARCHIVE=${ARCHIVE_BASE}.tar.gz"
  echo "ARCHIVE_SHA256=$(awk '{print $1}' "${CHECKSUMS}")"
  echo "SOURCE_ROOT=${SOURCE_ROOT}"
  if git -C "${SOURCE_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    echo "SOURCE_GIT_COMMIT=$(git -C "${SOURCE_ROOT}" rev-parse HEAD)"
    echo "SOURCE_GIT_BRANCH=$(git -C "${SOURCE_ROOT}" branch --show-current)"
    echo "SOURCE_GIT_STATUS_FILE=${ARCHIVE_BASE}.git-status"
    {
      for source in ise-agent ise-agent-container; do
        printf '[%s]\n' "${source}"
        git -C "${SOURCE_ROOT}/${source}" status --short
      done
    } > "${OUTPUT_DIR}/${ARCHIVE_BASE}.git-status"
  else
    echo "SOURCE_GIT_COMMIT=unavailable"
    echo "SOURCE_GIT_BRANCH=unavailable"
    echo "SOURCE_GIT_STATUS_FILE=unavailable"
  fi
  for source in ise-agent ise-agent-container; do
    key="$(printf '%s' "${source}" | tr '[:lower:]-' '[:upper:]_')"
    if git -C "${SOURCE_ROOT}/${source}" rev-parse HEAD >/dev/null 2>&1; then
      echo "${key}_GIT_COMMIT=$(git -C "${SOURCE_ROOT}/${source}" rev-parse HEAD)"
      echo "${key}_GIT_BRANCH=$(git -C "${SOURCE_ROOT}/${source}" branch --show-current)"
    else
      echo "${key}_GIT_COMMIT=unavailable"
      echo "${key}_GIT_BRANCH=unavailable"
    fi
  done
} > "${METADATA}"

echo "Created: ${ARCHIVE}"
echo "Checksum: ${CHECKSUMS}"
echo "Manifest: ${MANIFEST}"
echo "Metadata: ${METADATA}"
