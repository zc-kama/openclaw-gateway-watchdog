#!/usr/bin/env bash
# OpenClaw Gateway Watchdog
# Keeps the OpenClaw gateway/channel alive with layered probes and guarded restarts.

set -u

WATCHDOG_VERSION="1.0.0"

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/openclaw-gateway-watchdog"
CONFIG_FILE="${WATCHDOG_CONFIG:-${CONFIG_DIR}/watchdog.env}"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/openclaw-gateway-watchdog"
LOG_FILE="${WATCHDOG_LOG_FILE:-${STATE_DIR}/watchdog.log}"
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}"
RUNTIME_DIR="${RUNTIME_BASE}/openclaw-gateway-watchdog"
LOCK_DIR="${RUNTIME_DIR}/lock"

# Defaults are intentionally useful out of the box. Users can override them in
# ~/.config/openclaw-gateway-watchdog/watchdog.env or environment variables.
GATEWAY_SERVICE="${GATEWAY_SERVICE:-openclaw-gateway}"
GATEWAY_HEALTH_URL="${GATEWAY_HEALTH_URL:-http://127.0.0.1:18789/healthz}"
GATEWAY_HOST="${GATEWAY_HOST:-127.0.0.1}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
CHANNEL_URL="${CHANNEL_URL:-https://ilinkai.weixin.qq.com}"
NETWORK_URLS="${NETWORK_URLS:-https://www.baidu.com https://www.qq.com https://api.weixin.qq.com}"
RESTART_COMMAND="${RESTART_COMMAND:-}"

BASE_INTERVAL="${BASE_INTERVAL:-60}"
NIGHT_INTERVAL="${NIGHT_INTERVAL:-300}"
MAX_INTERVAL="${MAX_INTERVAL:-1800}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-10}"
CHANNEL_FAILURES_BEFORE_RESTART="${CHANNEL_FAILURES_BEFORE_RESTART:-2}"
SUCCESS_COUNT_TO_RESET="${SUCCESS_COUNT_TO_RESET:-5}"
MAX_RESTARTS_PER_HOUR="${MAX_RESTARTS_PER_HOUR:-6}"
POST_RESTART_SLEEP="${POST_RESTART_SLEEP:-30}"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

mkdir -p "$STATE_DIR" "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another watchdog instance is already running: $LOCK_DIR" >&2
  exit 0
fi
trap cleanup EXIT INT TERM

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE"
}

rotate_log_if_needed() {
  local max_bytes="${MAX_LOG_BYTES:-1048576}"
  [ -f "$LOG_FILE" ] || return 0
  local size
  size=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
  if [ "${size:-0}" -gt "$max_bytes" ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || : >"$LOG_FILE"
    log "LOG: rotated because it exceeded ${max_bytes} bytes"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

http_probe() {
  local url="$1"
  local code
  code=$(curl -L -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" "$url" 2>/dev/null || printf '000')

  case "$code" in
    2??|3??|4??) return 0 ;;
    *) return 1 ;;
  esac
}

tcp_probe() {
  [ -n "${GATEWAY_HOST:-}" ] || return 1
  [ -n "${GATEWAY_PORT:-}" ] || return 1
  ( : >"/dev/tcp/${GATEWAY_HOST}/${GATEWAY_PORT}" ) >/dev/null 2>&1
}

systemd_user_available() {
  have_cmd systemctl && systemctl --user status >/dev/null 2>&1
}

service_unit_name() {
  case "$GATEWAY_SERVICE" in
    *.service) printf '%s\n' "$GATEWAY_SERVICE" ;;
    *) printf '%s.service\n' "$GATEWAY_SERVICE" ;;
  esac
}

gateway_unit_exists() {
  local unit
  systemd_user_available || return 1
  unit=$(service_unit_name)
  [ "$(systemctl --user show "$unit" -p LoadState --value 2>/dev/null || echo not-found)" != "not-found" ]
}

gateway_unit_active() {
  systemd_user_available || return 1
  systemctl --user is-active --quiet "$GATEWAY_SERVICE" >/dev/null 2>&1
}

check_gateway() {
  if [ -n "${GATEWAY_HEALTH_URL:-}" ] && http_probe "$GATEWAY_HEALTH_URL"; then
    return 0
  fi

  if tcp_probe; then
    return 0
  fi

  if gateway_unit_exists; then
    if gateway_unit_active; then
      log "GATEWAY WARN: service is active, but local health/port probe failed"
      return 2
    fi
    log "GATEWAY FAIL: service ${GATEWAY_SERVICE} is not active"
    return 1
  fi

  if have_cmd pgrep && pgrep -f 'openclaw.*gateway' >/dev/null 2>&1; then
    log "GATEWAY WARN: process exists, but local health/port probe failed"
    return 2
  fi

  log "GATEWAY FAIL: no healthy gateway detected"
  return 1
}

check_channel() {
  http_probe "$CHANNEL_URL"
}

check_network() {
  local success=0
  local total=0
  local url

  for url in $NETWORK_URLS; do
    total=$((total + 1))
    if http_probe "$url"; then
      success=$((success + 1))
    fi
  done

  if [ "$success" -gt 0 ]; then
    return 0
  fi

  log "NETWORK FAIL: all ${total} network probes failed"
  return 1
}

restart_count_file() {
  printf '%s/restarts.%s' "$STATE_DIR" "$(date '+%Y%m%d%H')"
}

can_restart_now() {
  local file
  file=$(restart_count_file)
  local count=0
  [ -f "$file" ] && count=$(cat "$file" 2>/dev/null || echo 0)
  [ "${count:-0}" -lt "$MAX_RESTARTS_PER_HOUR" ]
}

record_restart() {
  local file
  file=$(restart_count_file)
  local count=0
  [ -f "$file" ] && count=$(cat "$file" 2>/dev/null || echo 0)
  printf '%s\n' "$((count + 1))" >"$file"
  find "$STATE_DIR" -name 'restarts.*' -type f -mtime +2 -delete 2>/dev/null || true
}

restart_gateway() {
  if ! can_restart_now; then
    log "CIRCUIT OPEN: restart limit reached (${MAX_RESTARTS_PER_HOUR}/hour); skip restart"
    return 1
  fi

  if [ -n "${RESTART_COMMAND:-}" ]; then
    log "ACTION: ${RESTART_COMMAND}"
    if sh -c "$RESTART_COMMAND" >>"$LOG_FILE" 2>&1; then
      record_restart
      return 0
    fi
    log "ACTION FAIL: restart command returned non-zero"
    return 1
  fi

  if gateway_unit_exists; then
    log "ACTION: systemctl --user restart ${GATEWAY_SERVICE}"
    if systemctl --user restart "$GATEWAY_SERVICE" >>"$LOG_FILE" 2>&1; then
      record_restart
      return 0
    fi
    log "ACTION FAIL: systemd restart failed"
    return 1
  fi

  if have_cmd openclaw; then
    log "ACTION: openclaw gateway restart"
    if openclaw gateway restart >>"$LOG_FILE" 2>&1; then
      record_restart
      return 0
    fi
    log "ACTION FAIL: openclaw gateway restart failed"
    return 1
  fi

  log "ACTION FAIL: set RESTART_COMMAND in ${CONFIG_FILE}; no restart method found"
  return 1
}

backoff_interval() {
  local failures="$1"
  local interval="$BASE_INTERVAL"
  local i=1
  while [ "$i" -lt "$failures" ]; do
    interval=$((interval * 2))
    i=$((i + 1))
    [ "$interval" -ge "$MAX_INTERVAL" ] && break
  done
  [ "$interval" -gt "$MAX_INTERVAL" ] && interval="$MAX_INTERVAL"
  printf '%s\n' "$interval"
}

sleep_interval() {
  local hour
  hour=$(date '+%H')
  hour=$((10#$hour))
  if [ "$hour" -ge 1 ] && [ "$hour" -lt 8 ]; then
    printf '%s\n' "$NIGHT_INTERVAL"
  else
    printf '%s\n' "$BASE_INTERVAL"
  fi
}

main() {
  local fail_count=0
  local success_count=0
  local gw_status=0
  local wait_for=0

  log "START: OpenClaw gateway watchdog ${WATCHDOG_VERSION}"
  log "CONFIG: ${CONFIG_FILE}"
  log "TARGET: channel=${CHANNEL_URL} health=${GATEWAY_HEALTH_URL} service=${GATEWAY_SERVICE}"

  while true; do
    rotate_log_if_needed

    check_gateway
    gw_status=$?
    if [ "$gw_status" -eq 1 ]; then
      fail_count=$((fail_count + 1))
      success_count=0
      log "CRITICAL: gateway appears down; restarting immediately"
      restart_gateway || true
      sleep "$POST_RESTART_SLEEP"
      continue
    fi

    if check_channel; then
      if [ "$fail_count" -gt 0 ]; then
        success_count=$((success_count + 1))
        if [ "$success_count" -ge "$SUCCESS_COUNT_TO_RESET" ]; then
          log "RECOVERED: ${SUCCESS_COUNT_TO_RESET} consecutive channel probes succeeded; failure count reset"
          fail_count=0
          success_count=0
        else
          log "RECOVERING: channel probe succeeded (${success_count}/${SUCCESS_COUNT_TO_RESET})"
        fi
      fi
      sleep "$(sleep_interval)"
      continue
    fi

    fail_count=$((fail_count + 1))
    success_count=0
    log "CHANNEL FAIL: ${CHANNEL_URL} failed (${fail_count}/${CHANNEL_FAILURES_BEFORE_RESTART})"

    if ! check_network; then
      log "SAFEGUARD: looks like global network trouble; wait without restarting gateway"
      sleep "$BASE_INTERVAL"
      continue
    fi

    if [ "$fail_count" -lt "$CHANNEL_FAILURES_BEFORE_RESTART" ]; then
      sleep "$BASE_INTERVAL"
      continue
    fi

    wait_for=$(backoff_interval "$fail_count")
    log "BACKOFF: network is reachable; will re-check channel in ${wait_for}s before restart"
    sleep "$wait_for"

    if check_channel; then
      log "RECOVERED: channel came back before restart"
      fail_count=0
      continue
    fi

    restart_gateway || true
    sleep "$POST_RESTART_SLEEP"
  done
}

main "$@"
