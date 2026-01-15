#!/usr/bin/env bash
set -euo pipefail

# --- Identity / IPC ---
TITLE="waybar_radio"
SOCKET="/tmp/mpv-waybar-radio.sock"

# --- State ---
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/waybar-radio"
STATE_FILE="$STATE_DIR/current_station"
mkdir -p "$STATE_DIR"

# --- Stations (name|url) ---
STATIONS=(
  # Classical
  "[Classical] Venice Classic Radio|http://de2.streamingpulse.com.:8010/stream"

  # SomaFM (highest available MP3 per channel) — no seasonal/Xmas channels
  "[Electronic] Beat Blender|https://somafm.com/beatblender.pls"
  "[Electronic] cliqhop idm|https://somafm.com/cliqhop256.pls"
  "[Electronic] Digitalis|https://somafm.com/digitalis256.pls"
  "[Electronic] Dub Step Beyond|https://somafm.com/dubstep256.pls"
  "[Electronic] Groove Salad|https://somafm.com/groovesalad256.pls"
  "[Electronic] Groove Salad Classic|https://somafm.com/gsclassic.pls"
  "[Electronic] Space Station Soma|https://somafm.com/spacestation320.pls"
  "[Electronic] Suburbs of Goa|https://somafm.com/suburbsofgoa.pls"
  "[Electronic] Synphaera Radio|https://somafm.com/synphaera256.pls"
  "[Electronic] The Trip|https://somafm.com/thetrip.pls"

  "[Ambient] Drone Zone|https://somafm.com/dronezone256.pls"
  "[Ambient] Mission Control|https://somafm.com/missioncontrol.pls"
  "[Ambient] The Dark Zone|https://somafm.com/darkzone256.pls"

  "[Indie] Indie Pop Rocks!|https://somafm.com/indiepop.pls"
  "[Indie] PopTron!|https://somafm.com/poptron.pls"

  "[Rock/Metal] Doomed|https://somafm.com/doomed256.pls"
  "[Rock/Metal] Metal Detector|https://somafm.com/metal.pls"

  "[Lounge/Jazz] Bossa Beyond|https://somafm.com/bossa256.pls"
  "[Lounge/Jazz] Illinois Street Lounge|https://somafm.com/illstreet.pls"
  "[Lounge/Jazz] Lush|https://somafm.com/lush.pls"
  "[Lounge/Jazz] Secret Agent|https://somafm.com/secretagent.pls"

  "[Soul/Funk] Seven Inch Soul|https://somafm.com/7soul.pls"
  "[Country/Americana] Boot Liquor|https://somafm.com/bootliquor320.pls"
  "[Reggae] Heavyweight Reggae|https://somafm.com/reggae256.pls"

  "[Eclectic] Covers|https://somafm.com/covers.pls"
  "[Eclectic] Deep Space One|https://somafm.com/deepspaceone.pls"
  "[Eclectic] Folk Forward|https://somafm.com/folkfwd.pls"
  "[Eclectic] Fluid|https://somafm.com/fluid.pls"
  "[Eclectic] Left Coast 70s|https://somafm.com/seventies.pls"
  "[Eclectic] Live|https://somafm.com/live.pls"
  "[Eclectic] Sonic Universe|https://somafm.com/sonicuniverse.pls"
  "[Eclectic] Specials|https://somafm.com/specials.pls"

  "[Security] DEF CON Radio|https://somafm.com/defcon256.pls"
  "[Chill] Chillits Radio|https://somafm.com/chillits256.pls"
)

# Default to first station if none selected yet
if [[ ! -f "$STATE_FILE" ]]; then
  echo "${STATIONS[0]%%|*}" > "$STATE_FILE"
fi

CURRENT_NAME="$(cat "$STATE_FILE")"

get_url_for_name() {
  local name="$1"
  local entry
  for entry in "${STATIONS[@]}"; do
    if [[ "${entry%%|*}" == "$name" ]]; then
      echo "${entry#*|}"
      return 0
    fi
  done
  return 1
}

CURRENT_URL="$(get_url_for_name "$CURRENT_NAME" || true)"

# --- Process/State helpers ---
is_running() {
  pgrep -f "mpv.*--title=$TITLE" >/dev/null 2>&1
}

# Treat "playing" as: mpv is running AND socket exists.
# This removes the orange "connecting" flicker caused by stale mpv processes or missing socket.
is_playing() {
  is_running && [[ -S "$SOCKET" ]]
}

stop_player() {
  if is_running; then
    pkill -f "mpv.*--title=$TITLE" || true

    # Wait briefly for mpv to exit so Waybar doesn't catch an in-between state.
    for _ in {1..10}; do
      is_running || break
      sleep 0.1
    done
  fi

  # Safe cleanup: only after mpv is gone (or we tried).
  rm -f "$SOCKET"
}

start_player() {
  local url="$1"
  stop_player
  mpv --no-video --title="$TITLE" --input-ipc-server="$SOCKET" "$url" >/dev/null 2>&1 &
  # Tiny delay so reporting sees the socket promptly
  sleep 0.1
}

refresh_waybar() {
  pkill -RTMIN+1 waybar || true
}

choose_station() {
  if command -v fuzzel >/dev/null 2>&1; then
    printf '%s\n' "${STATIONS[@]%%|*}" | \
      fuzzel --dmenu \
             --anchor=top \
             --prompt="Radio: "
  elif command -v wofi >/dev/null 2>&1; then
    printf '%s\n' "${STATIONS[@]%%|*}" | wofi --dmenu -p "Radio:"
  elif command -v rofi >/dev/null 2>&1; then
    printf '%s\n' "${STATIONS[@]%%|*}" | rofi -dmenu -p "Radio:"
  elif command -v bemenu >/dev/null 2>&1; then
    printf '%s\n' "${STATIONS[@]%%|*}" | bemenu -p "Radio:"
  else
    echo ""
  fi
}

# --- Actions ---
case "${1:-}" in
  --toggle)
    if is_running; then
      stop_player
    else
      [[ -n "${CURRENT_URL:-}" ]] && start_player "$CURRENT_URL"
    fi
    refresh_waybar
    exit 0
    ;;

  --menu)
    choice="$(choose_station)"
    [[ -z "$choice" ]] && exit 0

    url="$(get_url_for_name "$choice")"
    echo "$choice" > "$STATE_FILE"
    CURRENT_NAME="$choice"
    CURRENT_URL="$url"

    start_player "$url"
    refresh_waybar
    exit 0
    ;;
esac

# --- Reporting Logic (Waybar poll) ---
if is_playing; then
  LINE1="$CURRENT_NAME"
  LINE2=""

  RAW_METADATA="$(
    echo '{ "command": ["get_property", "media-title"] }' \
      | socat - "$SOCKET" 2>/dev/null \
      | jq -r '.data'
  )"

  CLEAN_METADATA="$(echo "$RAW_METADATA" | sed 's/ {+info:.*}//')"

  if [[ "$CLEAN_METADATA" != "null" && -n "$CLEAN_METADATA" ]]; then
    LINE2="$CLEAN_METADATA"
  else
    LINE2=""  # no more "(Connecting…)" spam
  fi

  TOOLTIP="$(printf "%s\n%s" "$LINE1" "$LINE2" | sed '/^$/d')"

  jq -nc --arg text "󰽰" --arg class "playing" --arg tooltip "$TOOLTIP" \
    '{text:$text, class:$class, tooltip:$tooltip}'
else
  jq -nc --arg text "󰽰" --arg class "stopped" --arg tooltip "Stopped — Right click to choose (${CURRENT_NAME})" \
    '{text:$text, class:$class, tooltip:$tooltip}'
fi
