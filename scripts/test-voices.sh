#!/usr/bin/env bash
set -euo pipefail

# Cycle through all installed Piper voices and speak a short line for each.
# Defaults to /usr/share/piper-voices and auto-detects an audio player (pw-play/paplay/aplay).

VOICES_DIR="${VOICES_DIR:-/usr/share/piper-voices}"
PAUSE_SECONDS="${PAUSE_SECONDS:-1}"
EXTRA_TEXT="${EXTRA_TEXT:-Arch Linux is the best.}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd piper-tts; then
  die "piper-tts not found in PATH. Install piper-tts (e.g. piper-tts-bin) and try again."
fi

# Pick an audio player
AUDIO_PLAYER=""
if need_cmd pw-play; then
  AUDIO_PLAYER="pw-play -"
elif need_cmd paplay; then
  AUDIO_PLAYER="paplay"
elif need_cmd aplay; then
  AUDIO_PLAYER="aplay"
else
  die "No audio player found. Install one of: pipewire-audio (pw-play), pulseaudio-utils (paplay), alsa-utils (aplay)."
fi

# Gather voices
mapfile -d '' -t VOICES < <(find "$VOICES_DIR" -type f -name '*.onnx' -print0 2>/dev/null | sort -z)

if ((${#VOICES[@]} == 0)); then
  die "No .onnx voices found under: $VOICES_DIR"
fi

echo "Found ${#VOICES[@]} voices under $VOICES_DIR"
echo "Using audio player: $AUDIO_PLAYER"
echo

say_with_voice() {
  local model="$1"
  local name="$2"
  local text="Hello. This is ${name}. ${EXTRA_TEXT}"

  # Use Piper to generate WAV to stdout and pipe to the player.
  # Note: pw-play requires '-' to read stdin (already included above).
  printf '%s' "$text" | piper-tts -q -m "$model" -f - | eval "$AUDIO_PLAYER" >/dev/null 2>&1
}

for model in "${VOICES[@]}"; do
  # Derive a friendly name from filename
  base="$(basename "$model")" # e.g. en_GB-alba-medium.onnx
  name="${base%.onnx}"        # e.g. en_GB-alba-medium

  echo "Speaking with: $name"
  if ! say_with_voice "$model" "$name"; then
    echo "  (Failed for $model)" >&2
  fi

  sleep "$PAUSE_SECONDS"
done

echo
echo "Done."
