#!/usr/bin/env bash
set -euo pipefail

SYMLINK="${HOME}/.current_wallpaper"

usage() {
  echo "Usage: wallpaper <image-path>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage

# Allow calling from any directory
INPUT="$1"

# Resolve to an absolute path, and ensure it exists
if [[ "$INPUT" != /* ]]; then
  INPUT="$(pwd)/$INPUT"
fi

if [[ ! -f "$INPUT" ]]; then
  echo "wallpaper: file not found: $INPUT" >&2
  exit 1
fi

# Optional: basic extension check (comment out if you want anything)
case "${INPUT,,}" in
*.jpg | *.jpeg | *.png | *.webp | *.bmp | *.tiff) ;;
*)
  echo "wallpaper: not a common image type: $INPUT" >&2
  echo "          (if it's valid for swaybg, remove the extension check)" >&2
  exit 1
  ;;
esac

# Update the symlink atomically-ish
ln -sfn "$INPUT" "$SYMLINK"

# Refresh swaybg (kill old, start new)
pkill -u "$USER" -x swaybg 2>/dev/null || true

# Give it a moment to actually exit
for _ in {1..20}; do
  pgrep -u "$USER" -x swaybg >/dev/null || break
  sleep 0.05
done

nohup swaybg -i "$SYMLINK" -m fill >/dev/null 2>&1 &
disown || true

echo "Wallpaper set -> $INPUT"
