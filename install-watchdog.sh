#!/usr/bin/env bash
# Install OpenClaw Gateway Watchdog for the current Linux/WSL user.

set -euo pipefail

SERVICE_NAME="gateway-watchdog"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/share/openclaw-gateway-watchdog}"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/openclaw-gateway-watchdog"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/openclaw-gateway-watchdog"
CONFIG_FILE="${CONFIG_DIR}/watchdog.env"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_USER_DIR}/${SERVICE_NAME}.service"

CHANNEL_URL="${CHANNEL_URL:-}"
GATEWAY_SERVICE="${GATEWAY_SERVICE:-}"
GATEWAY_HEALTH_URL="${GATEWAY_HEALTH_URL:-}"
RESTART_COMMAND="${RESTART_COMMAND:-}"
YES=0
NO_START=0

usage() {
  cat <<'USAGE'
Usage:
  bash install-watchdog.sh [options]

Options:
  --yes                         Non-interactive install with defaults.
  --no-start                    Install files/service but do not start it.
  --channel-url URL             Main channel URL to probe.
  --gateway-service NAME        systemd user service name, default auto/openclaw-gateway.
  --health-url URL              Local gateway health URL, default http://127.0.0.1:18789/healthz.
  --restart-command COMMAND     Explicit command used to restart gateway.
  --install-dir DIR             Override install directory.
  -h, --help                    Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y) YES=1 ;;
    --no-start) NO_START=1 ;;
    --channel-url) CHANNEL_URL="${2:?missing URL}"; shift ;;
    --gateway-service|--service) GATEWAY_SERVICE="${2:?missing service name}"; shift ;;
    --health-url) GATEWAY_HEALTH_URL="${2:?missing URL}"; shift ;;
    --restart-command) RESTART_COMMAND="${2:?missing command}"; shift ;;
    --install-dir) INSTALL_DIR="${2:?missing dir}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "Please run this installer inside WSL/Linux, not Git Bash/PowerShell." >&2
    exit 1
    ;;
esac

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

systemd_user_available() {
  have_cmd systemctl && systemctl --user status >/dev/null 2>&1
}

unit_exists() {
  local unit="$1"
  local service_unit
  systemd_user_available || return 1
  case "$unit" in
    *.service) service_unit="$unit" ;;
    *) service_unit="${unit}.service" ;;
  esac
  [ "$(systemctl --user show "$service_unit" -p LoadState --value 2>/dev/null || echo not-found)" != "not-found" ]
}

detect_gateway_service() {
  local candidate
  for candidate in openclaw-gateway openclaw.gateway openclaw; do
    if unit_exists "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' "openclaw-gateway"
}

default_restart_command() {
  local service="$1"
  if unit_exists "$service"; then
    printf 'systemctl --user restart %s\n' "$service"
  elif have_cmd openclaw; then
    printf '%s\n' 'openclaw gateway restart'
  else
    printf 'systemctl --user restart %s\n' "$service"
  fi
}

prompt_default() {
  local prompt="$1"
  local default="$2"
  local answer=""

  if [ "$YES" -eq 1 ] || [ ! -t 0 ]; then
    printf '%s\n' "$default"
    return 0
  fi

  printf '%s [%s]: ' "$prompt" "$default" >&2
  read -r answer || answer=""
  if [ -n "$answer" ]; then
    printf '%s\n' "$answer"
  else
    printf '%s\n' "$default"
  fi
}

require_cmd() {
  if ! have_cmd "$1"; then
    echo "Missing dependency: $1" >&2
    exit 1
  fi
}

require_cmd curl

GATEWAY_SERVICE="${GATEWAY_SERVICE:-$(detect_gateway_service)}"
CHANNEL_URL="${CHANNEL_URL:-$(prompt_default "Channel probe URL" "https://ilinkai.weixin.qq.com")}"
GATEWAY_HEALTH_URL="${GATEWAY_HEALTH_URL:-$(prompt_default "Local gateway health URL" "http://127.0.0.1:18789/healthz")}"
RESTART_COMMAND="${RESTART_COMMAND:-$(default_restart_command "$GATEWAY_SERVICE")}"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$STATE_DIR" "$SYSTEMD_USER_DIR"
install -m 0755 "${SCRIPT_DIR}/gateway-watchdog.sh" "${INSTALL_DIR}/gateway-watchdog.sh"
install -m 0755 "${SCRIPT_DIR}/uninstall-watchdog.sh" "${INSTALL_DIR}/uninstall-watchdog.sh"
[ -f "${SCRIPT_DIR}/README.md" ] && install -m 0644 "${SCRIPT_DIR}/README.md" "${INSTALL_DIR}/README.md"
[ -f "${SCRIPT_DIR}/README.zh-CN.md" ] && install -m 0644 "${SCRIPT_DIR}/README.zh-CN.md" "${INSTALL_DIR}/README.zh-CN.md"

if [ ! -f "$CONFIG_FILE" ]; then
  cat >"$CONFIG_FILE" <<EOF
# OpenClaw Gateway Watchdog config.
# Re-run install-watchdog.sh with flags or edit this file to override defaults.
GATEWAY_SERVICE="${GATEWAY_SERVICE}"
GATEWAY_HEALTH_URL="${GATEWAY_HEALTH_URL}"
GATEWAY_HOST="127.0.0.1"
GATEWAY_PORT="18789"
CHANNEL_URL="${CHANNEL_URL}"
NETWORK_URLS="https://www.baidu.com https://www.qq.com https://api.weixin.qq.com"
RESTART_COMMAND="${RESTART_COMMAND}"
BASE_INTERVAL="60"
NIGHT_INTERVAL="300"
MAX_INTERVAL="1800"
CHANNEL_FAILURES_BEFORE_RESTART="2"
SUCCESS_COUNT_TO_RESET="5"
MAX_RESTARTS_PER_HOUR="6"
EOF
else
  echo "Keeping existing config: ${CONFIG_FILE}"
fi

cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=OpenClaw Gateway Watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=WATCHDOG_CONFIG=${CONFIG_FILE}
ExecStart=${INSTALL_DIR}/gateway-watchdog.sh
Restart=always
RestartSec=20

[Install]
WantedBy=default.target
EOF

if systemd_user_available; then
  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_NAME"
  if [ "$NO_START" -eq 0 ]; then
    systemctl --user restart "$SERVICE_NAME"
  fi
  echo "Installed systemd user service: ${SERVICE_NAME}"
  echo "Status:  systemctl --user status ${SERVICE_NAME}"
  echo "Logs:    journalctl --user -u ${SERVICE_NAME} -f"
else
  echo "User systemd is not available. Installing direct-run fallback."
  if [ "$NO_START" -eq 0 ]; then
    nohup "${INSTALL_DIR}/gateway-watchdog.sh" >>"${STATE_DIR}/bootstrap.log" 2>&1 &
    printf '%s\n' "$!" >"${STATE_DIR}/watchdog.pid"
    echo "Started fallback process with PID $(cat "${STATE_DIR}/watchdog.pid")."
  fi
  echo "For automatic start after reboot, enable user systemd in WSL/Linux and re-run this installer."
fi

echo ""
echo "Config:  ${CONFIG_FILE}"
echo "Log:     ${STATE_DIR}/watchdog.log"
echo "Remove:  bash ${INSTALL_DIR}/uninstall-watchdog.sh"
