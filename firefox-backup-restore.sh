#!/usr/bin/env bash
set -euo pipefail
umask 077

# Backup/restore the entire ~/.mozilla directory to an encrypted archive.
# Prefers 7z (AES-256). Falls back to zip encryption (often weaker; commonly ZipCrypto).
#
# Usage:
#   ./firefox-backup-restore.sh backup  <name>
#   ./firefox-backup-restore.sh restore <archive.{7z|zip}>

die(){ echo "ERROR: $*" >&2; exit 1; }
warn(){ echo "WARNING: $*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

usage(){
  cat >&2 <<'EOF'
Usage:
  firefox-backup-restore.sh backup  <name>
  firefox-backup-restore.sh restore <archive.{7z|zip}>

Examples:
  ./firefox-backup-restore.sh backup  joe1717
  ./firefox-backup-restore.sh restore joe1717.7z
  ./firefox-backup-restore.sh restore joe1717.zip
EOF
  exit 2
}

check_zip_tools(){
  local missing=()
  have zip   || missing+=("zip")
  have unzip || missing+=("unzip")
  if (( ${#missing[@]} > 0 )); then
    die "Missing required tools: ${missing[*]}. Install them and re-run."
  fi
}

warn_if_no_7z(){
  if ! have 7z; then
    warn "7z not found. Falling back to encrypted zip (weaker than 7z/AES-256)."
  fi
}

prompt_passphrase(){
  local p1 p2
  while true; do
    read -r -s -p "Enter encryption password: " p1; echo
    [[ -n "$p1" ]] || { warn "Password cannot be empty."; continue; }
    read -r -s -p "Confirm encryption password: " p2; echo
    [[ "$p1" == "$p2" ]] || { warn "Passwords did not match. Try again."; continue; }
    PASSPHRASE="$p1"
    return 0
  done
}

safe_rm_mozilla(){
  [[ -n "${HOME:-}" ]] || die "HOME is not set."
  local target="$HOME/.mozilla"

  # Safety rails: refuse to delete if HOME looks odd
  [[ "$HOME" == /* ]] || die "Refusing to run: HOME is not an absolute path: $HOME"
  [[ "$target" == "$HOME/.mozilla" ]] || die "Refusing to delete unexpected path: $target"

  rm -rf -- "$target"
}

backup(){
  local name="${1:-}"
  [[ -n "$name" ]] || usage

  [[ -n "${HOME:-}" ]] || die "HOME is not set."
  [[ -d "$HOME/.mozilla" ]] || die "Nothing to back up: $HOME/.mozilla does not exist."

  check_zip_tools
  warn_if_no_7z
  prompt_passphrase

  local out
  if have 7z; then
    out="$PWD/${name}.7z"
    # -mhe=on encrypts file names too
    ( cd "$HOME" && 7z a -t7z -mx=9 -mhe=on -p"$PASSPHRASE" "$out" ".mozilla" >/dev/null )
  else
    out="$PWD/${name}.zip"

    # zip -e prompts on /dev/tty and ignores stdin. Use expect if available to avoid double prompting.
    if have expect; then
      PASSPHRASE="$PASSPHRASE" OUT="$out" HOME_DIR="$HOME" expect <<'EOF' >/dev/null
        log_user 0
        set timeout -1
        set pass $env(PASSPHRASE)
        set out  $env(OUT)
        set home $env(HOME_DIR)
        cd $home
        spawn zip -er $out .mozilla
        expect "Enter password:"
        send "$pass\r"
        expect "Verify password:"
        send "$pass\r"
        expect eof
EOF
    else
      warn "Using 'zip -P' to avoid a second password prompt; the password may be briefly visible via 'ps' to other local users."
      ( cd "$HOME" && zip -rq -P "$PASSPHRASE" "$out" ".mozilla" >/dev/null )
    fi
  fi

  echo "Backup completed: $out"
}

restore(){
  local archive="${1:-}"
  [[ -n "$archive" ]] || usage
  [[ -f "$archive" ]] || die "Archive not found: $archive"

  check_zip_tools
  warn_if_no_7z
  prompt_passphrase

  local ext="${archive##*.}"
  case "$ext" in
    7z|zip) ;;
    *) die "Unsupported archive type: .$ext (expected .7z or .zip)";;
  esac

  # Remove existing ~/.mozilla (per your requested logic)
  safe_rm_mozilla

  # Extract to $HOME, expecting the archive to contain a top-level ".mozilla/" directory
  case "$ext" in
    7z)
      have 7z || die "Cannot restore .7z: '7z' is not installed."
      7z x -y -p"$PASSPHRASE" -o"$HOME" "$archive" >/dev/null
      ;;
    zip)
      # Provide password via -P so we don't get prompted again
      unzip -q -P "$PASSPHRASE" "$archive" -d "$HOME"
      ;;
  esac

  [[ -d "$HOME/.mozilla" ]] || die "Restore failed: ~/.mozilla was not created. (Archive may not contain a top-level .mozilla directory.)"
  echo "Restore completed: $HOME/.mozilla"
}

main(){
  local cmd="${1:-}"
  case "$cmd" in
    backup)
      [[ $# -eq 2 ]] || usage
      backup "$2"
      ;;
    restore)
      [[ $# -eq 2 ]] || usage
      restore "$2"
      ;;
    -h|--help|"")
      usage
      ;;
    *)
      die "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
