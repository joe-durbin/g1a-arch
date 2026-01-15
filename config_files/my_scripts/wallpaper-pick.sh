#!/usr/bin/env bash

# --- Configuration ---
WP_DIR="$HOME/Wallpaper"
SETTER_SCRIPT="$HOME/.config/my_scripts/wallpaper-set.sh"

# --- Safety Checks ---
if [[ ! -d "$WP_DIR" ]]; then
  echo "Error: Wallpaper directory not found at $WP_DIR"
  exit 1
fi

if [[ ! -x "$SETTER_SCRIPT" ]]; then
  echo "Error: Setter script not found or not executable at $SETTER_SCRIPT"
  exit 1
fi

# --- The "Slick" Picker ---
# 1. We use find to handle filenames with spaces.
# 2. The preview command uses the Kitty 'Delete All' escape sequence.
# 3. A 0.05s sleep prevents the race condition causing the overlap.
# 4. Quadruple backslashes ensure the sequence passes through the script shell correctly.

SELECTED=$(find "$WP_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.jpeg" \) | fzf \
  --preview 'printf "\033_Ga=d,d=a;\033\\\\"; sleep 0.05; chafa --format=kitty --size=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES} {}' \
  --preview-window='top:80%:border-rounded' \
  --prompt="󰸉 Wallpapers > " \
  --header="[Enter] Set Wallpaper | [Esc] Exit" \
  --layout=reverse \
  --border=none)

# --- Action ---
if [[ -n "$SELECTED" ]]; then
  # Directly calling the script to bypass alias issues
  "$SETTER_SCRIPT" "$SELECTED"
  echo "Wallpaper updated to: $(basename "$SELECTED")"
else
  echo "Selection cancelled."
fi
