#!/bin/bash

LOCK_FILE="/tmp/lid-inhibitor.lock"

# Check if an inhibitor is already running
if [ -f "$LOCK_FILE" ]; then
  PID=$(cat "$LOCK_FILE")
  # Check if the process actually exists before trying to kill
  if ps -p "$PID" >/dev/null; then
    kill "$PID"
    MSG="Laptop Mode: Lid will now SUSPEND."
  else
    MSG="Cleaned up stale lock. Laptop Mode active."
  fi
  rm "$LOCK_FILE"
else
  # Start inhibitor in background
  systemd-inhibit --what=handle-lid-switch --who="ToggleScript" --why="SSH Server Mode" --mode=block sleep infinity >/dev/null 2>&1 &
  echo $! >"$LOCK_FILE"
  MSG="Server Mode: Lid sleep IGNORED."
fi

# Only send notification if a Display is detected (GUI session)
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
  notify-send "Power Management" "$MSG" --icon=network-transmit
else
  echo "$MSG"
fi
