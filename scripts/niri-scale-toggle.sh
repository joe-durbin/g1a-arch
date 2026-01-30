#!/usr/bin/env bash
# Toggle niri screen scaling between current value and 1 for the focused output only.
# Does not modify the niri config file; uses runtime IPC only.

set -e

STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/niri-scale-state"

get_focused_output_and_scale() {
    niri msg focused-output 2>/dev/null | awk '
        /^Output .* \(.*\)$/ {
            match($0, /\([^)]+\)$/)
            name = substr($0, RSTART+1, RLENGTH-2)
            scale = ""
        }
        /^  Scale: / {
            scale = $2
        }
        /^  Disabled$/ {
            scale = ""
        }
        END {
            if (name != "" && scale != "") print name, scale
        }
    '
}

focused=$(get_focused_output_and_scale)

if [[ -f "$STATE_FILE" ]]; then
    # Restore saved scale for the output we had toggled
    while IFS= read -r line; do
        output="${line%% *}"
        scale="${line#* }"
        niri msg output "$output" scale "$scale" 2>/dev/null || true
    done < "$STATE_FILE"
    rm -f "$STATE_FILE"
else
    # Toggle only the currently focused output
    if [[ -z "$focused" ]]; then
        echo "niri-scale-toggle: no focused output or output has no scale (disabled?)" >&2
        exit 1
    fi
    output="${focused%% *}"
    scale="${focused#* }"
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$output $scale" > "$STATE_FILE"
    niri msg output "$output" scale 1 2>/dev/null || true
fi
