#!/usr/bin/env bash
#
# ISE Agent start script.
#
# Thin wrapper: detects docker/podman, then delegates interactive setup to
# scripts that run inside the agent container. The container handles all
# credential encryption, .env manipulation, and ISE connectivity checks.
#
# Usage:
#   ./start.sh                  # Normal start (runs first-run setup if needed)
#   ./start.sh --reconfigure    # Re-enter ISE credentials
#   ./start.sh --enable-pxgrid  # Enable real-time session monitoring via pxGrid
#   ./start.sh --disable-pxgrid # Revert to MnT polling for sessions
#   ./start.sh --update         # Pull the latest image and restart the agent
#   ./start.sh --no-pull        # Skip image pull for offline/local-image environments
#   ./start.sh --stop           # Stop the agent
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

CREDENTIALS_FILE="./certs/.credentials.enc"
KEY_FILE="./certs/private.pem.key"
CERT_FILE="./certs/certificate.pem.crt"

IMAGE="ghcr.io/duosecurity/ise-agent:latest"
CONTAINER_NAME=$(grep 'container_name:' docker-compose.yml | head -1 | awk '{print $2}' 2>/dev/null || echo "ise-agent")
PULL_IMAGE=1
IMAGE_PULLED=0
ISE_AGENT_NETWORK_MODE="bridge"
ISE_AGENT_DNS_SERVERS=()
ISE_AGENT_DNS_MODE="${ISE_AGENT_DNS_MODE:-auto}"
COMPOSE_GENERATED_OVERRIDE_FILE="./docker-compose.generated.yml"
COMPOSE_LEGACY_DNS_OVERRIDE_FILE="./docker-compose.dns.yml"

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

host_has_ipv6_default_route() {
  ip -6 route show default 2>/dev/null | grep -q .
}

detect_network_mode() {
  if host_has_ipv6_default_route; then
    ISE_AGENT_NETWORK_MODE="host"
    echo "IPv6-capable host detected; using host networking for ISE agent."
  else
    ISE_AGENT_NETWORK_MODE="bridge"
  fi
  export ISE_AGENT_NETWORK_MODE
}

detect_dns_servers() {
  local dns_server
  local resolv_conf
  local resolv_conf_dns_servers
  ISE_AGENT_DNS_SERVERS=()

  case "${ISE_AGENT_DNS_MODE}" in
    never|off|false|0)
      return
      ;;
    auto)
      if [[ "${ISE_AGENT_NETWORK_MODE}" == "host" ]]; then
        return
      fi

      resolv_conf="/etc/resolv.conf"
      if [[ -r "${resolv_conf}" ]]; then
        resolv_conf_dns_servers=()
        while read -r dns_server; do
          [[ -n "${dns_server}" ]] && resolv_conf_dns_servers+=("${dns_server}")
        done < <(
          awk '
            /^nameserver[[:space:]]+/ {
              if ($2 !~ /^(127\.|::1$)/) {
                print $2
              }
            }
          ' "${resolv_conf}"
        )
        if [[ "${#resolv_conf_dns_servers[@]}" -gt 0 ]]; then
          return
        fi
      fi
      ;;
    always|on|true|1)
      ;;
    *)
      echo "Error: ISE_AGENT_DNS_MODE must be auto, always, or never." >&2
      exit 1
      ;;
  esac

  for resolv_conf in /etc/resolv.conf /run/systemd/resolve/resolv.conf; do
    [[ -r "${resolv_conf}" ]] || continue
    resolv_conf_dns_servers=()
    while read -r dns_server; do
      [[ -n "${dns_server}" ]] && resolv_conf_dns_servers+=("${dns_server}")
    done < <(
      awk '
        /^nameserver[[:space:]]+/ {
          if ($2 !~ /^(127\.|::1$)/) {
            print $2
          }
        }
      ' "${resolv_conf}"
    )
    if [[ "${#resolv_conf_dns_servers[@]}" -gt 0 ]]; then
      ISE_AGENT_DNS_SERVERS=("${resolv_conf_dns_servers[@]}")
      echo "Using explicit DNS servers for ISE agent containers from ${resolv_conf}."
      return
    fi
  done
}

write_compose_generated_override() {
  local dns_server
  rm -f "${COMPOSE_LEGACY_DNS_OVERRIDE_FILE}"
  if [[ "${ISE_AGENT_NETWORK_MODE}" == "host" ]] || [[ "${#ISE_AGENT_DNS_SERVERS[@]}" -gt 0 ]]; then
    cat > "${COMPOSE_GENERATED_OVERRIDE_FILE}" <<EOF
services:
  ise-agent:
EOF
    if [[ "${ISE_AGENT_NETWORK_MODE}" == "host" ]]; then
      printf '    network_mode: host\n' >> "${COMPOSE_GENERATED_OVERRIDE_FILE}"
    fi
    if [[ "${#ISE_AGENT_DNS_SERVERS[@]}" -gt 0 ]]; then
      printf '    dns:\n' >> "${COMPOSE_GENERATED_OVERRIDE_FILE}"
    fi
    for dns_server in "${ISE_AGENT_DNS_SERVERS[@]}"; do
      printf '      - %s\n' "${dns_server}" >> "${COMPOSE_GENERATED_OVERRIDE_FILE}"
    done
  else
    rm -f "${COMPOSE_GENERATED_OVERRIDE_FILE}"
  fi
}

# -- Container helpers --

check_prerequisites() {
  if [[ -z "${RUNTIME}" ]]; then
    echo "Error: No container runtime found. Install docker or podman." >&2
    exit 1
  fi
  for f in "${KEY_FILE}" "${CERT_FILE}" ".env"; do
    if [[ ! -f "${f}" ]]; then
      echo "Error: ${f} not found. Make sure you've extracted the full agent package." >&2
      exit 1
    fi
  done
}

pull_image_once() {
  if [[ "${PULL_IMAGE}" != "1" ]] || [[ "${IMAGE_PULLED}" == "1" ]]; then
    return
  fi

  echo "Pulling latest ISE agent image..."
  ${RUNTIME} pull "${IMAGE}"
  IMAGE_PULLED=1
}

run_in_container() {
  # Run a one-off container with certs mounted so setup scripts can read/write
  # the encrypted credential stores without the host knowing their layout.
  pull_image_once
  local script="$1"
  shift
  local tty_args=()
  local network_args=()
  local dns_args=()
  local dns_server
  [[ -t 0 ]] && tty_args=(-t)
  [[ "${ISE_AGENT_NETWORK_MODE}" == "host" ]] && network_args=(--network host)
  for dns_server in "${ISE_AGENT_DNS_SERVERS[@]}"; do
    dns_args+=(--dns "${dns_server}")
  done
  ${RUNTIME} run --rm --pull=never "${network_args[@]}" "${dns_args[@]}" -i "${tty_args[@]}" \
    --env-file "$(pwd)/.env" \
    -v "$(pwd)/certs:/app/certs" \
    --entrypoint python "${IMAGE}" -u "/app/${script}" "$@"
}

compose_restart() {
  compose_cmd down 2>/dev/null || true
  compose_cmd up -d
  echo "View logs: ${RUNTIME} logs -f ${CONTAINER_NAME}"
}

compose_cmd() {
  if [[ -f "${COMPOSE_GENERATED_OVERRIDE_FILE}" ]]; then
    local compose_file
    local compose_candidate
    local compose_path_separator="${COMPOSE_PATH_SEPARATOR:-:}"
    if [[ -n "${COMPOSE_FILE:-}" ]]; then
      compose_file="${COMPOSE_FILE}${compose_path_separator}${COMPOSE_GENERATED_OVERRIDE_FILE}"
    else
      compose_file=""
      for compose_candidate in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        if [[ -f "${compose_candidate}" ]]; then
          compose_file="${compose_candidate}"
          break
        fi
      done
      if [[ -z "${compose_file}" ]]; then
        compose_file="docker-compose.yml"
      fi
      for compose_candidate in compose.override.yaml compose.override.yml docker-compose.override.yaml docker-compose.override.yml; do
        if [[ -f "${compose_candidate}" ]]; then
          compose_file="${compose_file}${compose_path_separator}${compose_candidate}"
        fi
      done
      compose_file="${compose_file}${compose_path_separator}${COMPOSE_GENERATED_OVERRIDE_FILE}"
    fi
    COMPOSE_FILE="${compose_file}" ${COMPOSE_CMD} "$@"
  else
    ${COMPOSE_CMD} "$@"
  fi
}

# -- Main --

ACTION=""
for arg in "$@"; do
  case "${arg}" in
    --reconfigure) ACTION="reconfigure" ;;
    --stop) ACTION="stop" ;;
    --update) ACTION="update" ;;
    --enable-pxgrid) ACTION="enable-pxgrid" ;;
    --disable-pxgrid) ACTION="disable-pxgrid" ;;
    --no-pull) PULL_IMAGE=0 ;;
    *) echo "Unknown option: ${arg}" >&2; exit 1 ;;
  esac
done

if [[ -z "${COMPOSE_CMD}" ]]; then
  echo "Error: No container runtime found. Install docker or podman." >&2
  exit 1
fi

detect_network_mode
detect_dns_servers
write_compose_generated_override

if [[ "${ACTION}" == "stop" ]]; then
  echo "Stopping ISE agent..."
  compose_cmd down
  exit 0
fi

if [[ "${ACTION}" == "update" ]]; then
  if [[ "${PULL_IMAGE}" != "1" ]]; then
    echo "Skipping image pull (--no-pull). Restarting with local image."
  fi
  pull_image_once
  compose_restart
  exit 0
fi

check_prerequisites

if [[ "${ACTION}" == "enable-pxgrid" ]]; then
  run_in_container setup_pxgrid.py enable
  compose_restart
  exit 0
fi

if [[ "${ACTION}" == "disable-pxgrid" ]]; then
  run_in_container setup_pxgrid.py disable
  compose_restart
  exit 0
fi

FIRST_RUN=0
if [[ "${ACTION}" == "reconfigure" ]] || [[ ! -f "${CREDENTIALS_FILE}" ]]; then
  [[ ! -f "${CREDENTIALS_FILE}" ]] && FIRST_RUN=1
  echo ""
  echo "Running ISE credential setup inside container..."
  run_in_container setup_credentials.py
fi

# On first run only (no pxGrid state yet), ask whether to enable pxGrid.
if [[ "${FIRST_RUN}" == "1" ]] && [[ ! -f "./certs/.pxgrid.enc" ]]; then
  run_in_container setup_pxgrid.py first-run
fi

echo ""
echo "Starting ISE agent..."
pull_image_once
compose_cmd up -d
echo ""
echo "ISE agent is running. View logs with: ${RUNTIME} logs -f ${CONTAINER_NAME}"
