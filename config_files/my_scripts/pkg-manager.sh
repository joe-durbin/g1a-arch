#!/bin/bash

# Configuration
PAC_LOG="$HOME/packages-pacman.txt"
AUR_LOG="$HOME/packages-aur.txt"

# Ensure files exist
touch "$PAC_LOG" "$AUR_LOG"

# Helper to check if a package is in the official repositories
is_repo_pkg() {
  pacman -Si "$1" >/dev/null 2>&1
}

# 1. Install Logic
install_pkg() {
  local source_cmd=$1
  local pkgs

  pkgs=$($source_cmd | fzf --multi --preview 'yay -Si {1}' --header "Select to Install")

  if [ -n "$pkgs" ]; then
    echo "$pkgs" | while read -r pkg; do
      if is_repo_pkg "$pkg"; then
        awk -v "pkg=$pkg" 'BEGIN{r=1} $0==pkg{r=0;exit} END{exit r}' "$PAC_LOG" || echo "$pkg" >>"$PAC_LOG"
      else
        awk -v "pkg=$pkg" 'BEGIN{r=1} $0==pkg{r=0;exit} END{exit r}' "$AUR_LOG" || echo "$pkg" >>"$AUR_LOG"
      fi
      echo "$pkg"
    done | xargs -ro yay -S
  fi
}

# 2. Remove Logic
remove_pkg() {
  local pkgs
  pkgs=$(pacman -Qeq | fzf --multi --preview 'yay -Si {1}' --header "Select to REMOVE")

  if [ -n "$pkgs" ]; then
    echo "$pkgs" | xargs -ro sudo pacman -Rs
    for pkg in $pkgs; do
      sed -i "/^$pkg$/d" "$PAC_LOG"
      sed -i "/^$pkg$/d" "$AUR_LOG"
    done
    echo "Logs updated: Cleaned $PAC_LOG and $AUR_LOG"
  fi
}

# 3. Sync Logic (Rebuilds logs from system state)
sync_logs() {
  echo "Scanning system and rebuilding logs..."

  # Create temporary files to prevent data loss if interrupted
  local tmp_pac=$(mktemp)
  local tmp_aur=$(mktemp)

  # Get all explicitly installed packages
  pacman -Qeq | while read -r pkg; do
    if is_repo_pkg "$pkg"; then
      echo "$pkg" >>"$tmp_pac"
    else
      echo "$pkg" >>"$tmp_aur"
    fi
  done

  # Sort and move to final destination
  sort -u "$tmp_pac" >"$PAC_LOG"
  sort -u "$tmp_aur" >"$AUR_LOG"
  rm "$tmp_pac" "$tmp_aur"

  echo "Done! $(wc -l <"$PAC_LOG") official and $(wc -l <"$AUR_LOG") AUR packages logged."
}

case "$1" in
p) install_pkg "pacman -Slq" ;;
y) install_pkg "yay -Slq --aur" ;;
r) remove_pkg ;;
sync) sync_logs ;;
*) echo "Usage: pkg-manager.sh {p|y|r|sync}" ;;
esac
