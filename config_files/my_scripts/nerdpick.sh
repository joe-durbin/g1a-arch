#!/bin/bash

# --- Configuration ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nerd-font-picker"
CACHE_FILE="$CACHE_DIR/formatted_list.txt"
JSON_FILE="$CACHE_DIR/glyphnames.json"
URL="https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json"

mkdir -p "$CACHE_DIR"

# --- Tools ---
if command -v pbcopy >/dev/null; then CLIP="pbcopy"
elif command -v xclip >/dev/null; then CLIP="xclip -sel clip"
elif command -v wl-copy >/dev/null; then CLIP="wl-copy"
else CLIP="cat"; fi

# --- Functions ---
refresh_cache() {
    echo "Updating icon cache... please wait."
    curl -sSLo "$JSON_FILE" "$URL"

    jq -r 'to_entries[] | select(.key != "METADATA" and .value.code != null) | "\(.value.code) \(.key)"' "$JSON_FILE" | grep -v "null" | while read -r hex name; do
        if [[ "$hex" =~ ^[0-9a-fA-F]+$ ]]; then
            symbol=$(printf "\\U$hex")
            printf " %s  \033[38;5;15m%-45s\033[0m \033[38;5;242m[%s]\033[0m\n" "$symbol" "$name" "$hex"
        fi
    done > "$CACHE_FILE"

    sed -i '/METADATA/d; /null/d; /^[[:space:]]*$/d' "$CACHE_FILE"
}

# --- Argument Handling ---
# If the first argument is --refresh, update the cache and then SHIFT it away
if [[ "$1" == "--refresh" ]]; then
    refresh_cache
    shift # This removes '--refresh' from the positional parameters
fi

# Auto-refresh if the cache file is totally missing
if [[ ! -f "$CACHE_FILE" ]]; then
    refresh_cache
fi

# --- The Interface ---
# Now $1 will be empty (unless you typed something else after --refresh)
selected=$(fzf --ansi \
    --query="$1" \
    --header=" [ENTER] Copy Symbol  |  [ESC] Exit" \
    --header-first \
    --prompt="   Search Icons: " \
    --pointer="➜" \
    --color="header:italic:cyan,prompt:bold:yellow,pointer:bold:red" < "$CACHE_FILE")

# --- Handle Selection ---
if [ -n "$selected" ]; then
    hex=$(echo "$selected" | grep -oP '\[\K[^\]]+')
    if [[ -n "$hex" && "$hex" =~ ^[0-9a-fA-F]+$ ]]; then
        symbol=$(printf "\\U$hex")
        echo -n "$symbol" | $CLIP
        echo "✔ Copied $symbol to clipboard."
    fi
fi
