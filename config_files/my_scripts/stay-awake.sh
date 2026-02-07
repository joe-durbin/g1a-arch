#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/tmp/lid-inhibitor.lock"

# True if lid-sleep inhibitor is active (lock exists and process is alive)
is_active() {
  [[ -f "$LOCK_FILE" ]] || return 1
  local pid
  pid=$(cat "$LOCK_FILE")
  [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1
}

refresh_waybar() {
  pkill -RTMIN+1 waybar 2>/dev/null || true
}

do_toggle() {
  local msg
  if is_active; then
    local pid
    pid=$(cat "$LOCK_FILE")
    kill "$pid" 2>/dev/null || true
    rm -f "$LOCK_FILE"
    msg="Laptop Mode: Lid will now SUSPEND."
  else
    # Clean stale lock if present, then start inhibitor
    rm -f "$LOCK_FILE"
    systemd-inhibit --what=handle-lid-switch --who="ToggleScript" --why="Dock/Stay Awake" --mode=block sleep infinity >/dev/null 2>&1 &
    echo $! >"$LOCK_FILE"
    msg="Server Mode: Lid sleep IGNORED (close lid OK)."
  fi

  if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    notify-send "Power Management" "$msg" --icon=network-transmit
  else
    echo "$msg"
  fi

  refresh_waybar
}

# --- Waybar status (no args): output JSON for custom module
if [[ $# -eq 0 ]]; then
  if is_active; then
    jq -nc \
      --arg text "󰅶" \
      --arg class "active" \
      --arg tooltip "Stay awake: ON — lid close ignored (click to turn off)" \
      '{text:$text, class:$class, tooltip:$tooltip}'
  else
    jq -nc \
      --arg text "󰅶" \
      --arg class "inactive" \
      --arg tooltip "Stay awake: OFF — lid will suspend (click to turn on)" \
      '{text:$text, class:$class, tooltip:$tooltip}'
  fi
  exit 0
fi

# --- Toggle on --toggle
if [[ "${1:-}" == "--toggle" ]]; then
  do_toggle
  exit 0
fi

# Unknown argument
echo "Usage: $0 [--toggle]" >&2
exit 1
