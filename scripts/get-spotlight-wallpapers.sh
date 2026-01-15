#!/bin/bash

SAVE_DIR="$HOME/Wallpaper/Spotlight"
mkdir -p "$SAVE_DIR"
UA="WindowsShellClient/0"
PID="338387"

REGIONS=("en-US/us" "en-GB/gb" "en-CA/ca" "en-AU/au" "de-DE/de" "fr-FR/fr")

echo "Harvesting Spotlight images..."

for reg in "${REGIONS[@]}"; do
  IFS="/" read -r locale ctry <<<"$reg"
  echo "--- Region: $ctry ---"

  API_URL="https://arc.msn.com/v3/Delivery/Placement?pid=$PID&fmt=json&ua=WindowsShellClient%2F0&cdm=1&disphorzres=1920&dispvertres=1080&lo=80217&pl=$locale&lc=$locale&ctry=$ctry"

  RAW_DATA=$(curl -sL -H "User-Agent: $UA" "$API_URL")

  # This refined JQ looks specifically for the .tx suffix Microsoft used in your log
  DATA_PAIRS=$(echo "$RAW_DATA" | jq -r '
      .batchrsp.items[]? |
      .item |
      fromjson |
      .ad |
      select(.image_fullscreen_001_landscape.u != null and (.image_fullscreen_001_landscape.u | contains("empty.jpg") | not)) |
      # Prioritize .title_text.tx as seen in your JSON dump
      (.title_text.tx // .title.text // .landing_page_title // "untitled") + "\t" + .image_fullscreen_001_landscape.u
    ' 2>/dev/null)

  [[ -z "$DATA_PAIRS" ]] && continue

  echo "$DATA_PAIRS" | while IFS=$'\t' read -r title url; do

    # If title is untitled or a placeholder, scrape the descriptive name from the URL
    if [[ "$title" == "untitled" || "$title" == "null" ]]; then
      # Scrapes the "aostavalleyitaly" part from the URL
      title=$(echo "$url" | grep -oE "wl_[a-z0-9]+" | sed 's/wl_//')
      [[ -z "$title" ]] && title=$(echo "$url" | md5sum | cut -c 1-8)
    fi

    # Clean name: remove special chars, replace spaces with underscores
    clean_name=$(echo "$title" | sed 's/[^a-zA-Z0-9 ]//g' | tr ' ' '_' | tr '[:upper:]' '[:lower:]' | cut -c1-50)
    target="$SAVE_DIR/${clean_name}.jpg"

    if [[ ! -f "$target" ]]; then
      echo "Downloading: ${clean_name}.jpg"
      curl -sL "$url" -o "$target"
    else
      echo "Already exists: ${clean_name}.jpg"
    fi
  done
done

declare -A hashes

echo "Cleaning up duplicates in $SAVE_DIR..."

find "$SAVE_DIR" -type f -name "*.jpg" -exec md5sum {} + | \
  sort | \
  awk 'BEGIN{last=""} {if($1==last) { $1=""; print substr($0,2) } else last=$1}' | \
  xargs -d '\n' -t -r rm

echo "De-duplication complete."

echo "---"
echo "Check $SAVE_DIR"
