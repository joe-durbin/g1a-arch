#!/usr/bin/env bash
set -euo pipefail

# -------------------------------------------------------------------
# Microsoft Cloud Attack & Defense tools box - host install script
# Converted from the provided Dockerfile.
#
# Target OS: Ubuntu 24.04 (noble)
# Run as a NON-root user with sudo privileges.
#
# Notes:
# - Installs system packages via apt.
# - Installs pipx packages into /opt/pipx (owned by the invoking user).
# - Clones repos into /opt/pentest-azure (owned by the invoking user).
# - Adds PATH + pipx env via /etc/profile.d/pentest-tools.sh
# - Adds bashrc block (idempotent) for bash-completion + starship + aliases.
# -------------------------------------------------------------------

INSTALL_DIR="${INSTALL_DIR:-/opt/pentest-azure}"
PIPX_HOME="${PIPX_HOME:-/opt/pipx}"
PIPX_BIN_DIR="${PIPX_BIN_DIR:-/opt/pipx/bin}"

# Starship config (optional): expected alongside this script in config_files/starship.toml
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STARSHIP_SRC="${STARSHIP_SRC:-${SCRIPT_DIR}/config_files/starship.toml}"

# Repos to clone
declare -a REPOS=(
  "https://github.com/Gerenios/AADInternals|AADInternals"
  "https://github.com/dafthack/GraphRunner|GraphRunner"
  "https://github.com/f-bader/TokenTacticsV2|TokenTacticsV2"
  "https://github.com/dafthack/MFASweep|MFASweep"
  "https://github.com/urbanadventurer/username-anarchy|username-anarchy"
  "https://github.com/yuyudhn/AzSubEnum|AzSubEnum"
  "https://github.com/joswr1ght/basicblobfinder|basicblobfinder"
  "https://github.com/gremwell/o365enum|o365enum"
  "https://github.com/0xZDH/o365spray|o365spray"
  "https://github.com/0xZDH/Omnispray|Omnispray"
  "https://github.com/dievus/Oh365UserFinder|Oh365UserFinder"
  "https://github.com/dafthack/MSOLSpray|MSOLSpray"
  "https://github.com/mlcsec/Graphpython|Graphpython"
  "https://github.com/hac01/uwg|uwg"
)

log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

sudo_keepalive() {
  # Prompt once up front.
  sudo -v
  # Keep sudo alive until script exits.
  while true; do
    sudo -n true >/dev/null 2>&1 || true
    sleep 60
  done &
  SUDO_KA_PID="$!"
  trap '[[ -n "${SUDO_KA_PID:-}" ]] && kill "${SUDO_KA_PID}" >/dev/null 2>&1 || true' EXIT
}

write_profile_d() {
  local f="/etc/profile.d/pentest-tools.sh"
  sudo tee "$f" >/dev/null <<EOF
# Added by pentest tools installer
export PIPX_HOME="${PIPX_HOME}"
export PIPX_BIN_DIR="${PIPX_BIN_DIR}"
export PATH="${PIPX_BIN_DIR}:\$PATH"
EOF
  sudo chmod 0644 "$f"
}

install_apt_packages() {
  log "Installing base packages via apt..."
  sudo apt-get update
  sudo apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    ca-certificates \
    gnupg \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    jq \
    libxml2-utils \
    hashcat \
    ruby-full \
    build-essential \
    zlib1g-dev \
    libssl-dev \
    libreadline-dev \
    pkg-config \
    bash-completion \
    bat \
    eza \
    nano \
    vim \
    sudo

  # Dockerfile removes apt lists; not necessary on host, but keep disk tidy.
  sudo rm -rf /var/lib/apt/lists/*
}

setup_pipx_dirs() {
  log "Creating pipx directories (${PIPX_HOME}, ${PIPX_BIN_DIR})..."
  sudo mkdir -p "${PIPX_HOME}" "${PIPX_BIN_DIR}"
  sudo chown -R "$(id -u)":"$(id -g)" "${PIPX_HOME}"

  # Ensure pipx uses our locations for this script run
  export PIPX_HOME PIPX_BIN_DIR
  export PATH="${PIPX_BIN_DIR}:${PATH}"

  # Also ensure future shells get PATH
  write_profile_d

  # pipx ensurepath is typically user-shell oriented; we handle PATH via profile.d above.
  pipx ensurepath >/dev/null 2>&1 || true
}

setup_bat_shim() {
  # Ubuntu uses batcat; provide /usr/local/bin/bat
  if command -v batcat >/dev/null 2>&1; then
    log "Creating /usr/local/bin/bat -> /usr/bin/batcat shim..."
    sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
  fi
}

install_powershell() {
  if command -v pwsh >/dev/null 2>&1; then
    log "PowerShell already present; skipping."
    return 0
  fi

  log "Installing PowerShell from Microsoft repo (Ubuntu 24.04 / noble)..."
  local deb="/tmp/packages-microsoft-prod.deb"
  curl -sSL -o "$deb" "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb"
  sudo dpkg -i "$deb"
  rm -f "$deb"
  sudo apt-get update
  sudo apt-get install -y powershell
  sudo rm -rf /var/lib/apt/lists/*
}

install_jwt_cli() {
  if command -v jwt >/dev/null 2>&1; then
    log "jwt-cli already present; skipping."
    return 0
  fi

  log "Installing jwt-cli from GitHub releases..."
  require_cmd jq
  local ver
  ver="$(curl -s https://api.github.com/repos/mike-engel/jwt-cli/releases/latest | jq -r '.tag_name')"
  [[ -n "$ver" && "$ver" != "null" ]] || die "Could not determine jwt-cli latest tag_name"

  local tgz="/tmp/jwt-linux.tar.gz"
  curl -sSL -o "$tgz" "https://github.com/mike-engel/jwt-cli/releases/download/${ver}/jwt-linux.tar.gz"
  tar -xzf "$tgz" -C /tmp
  sudo mv /tmp/jwt /usr/local/bin/jwt
  sudo chmod 0755 /usr/local/bin/jwt
  rm -f "$tgz"
}

install_azurehound() {
  if command -v azurehound >/dev/null 2>&1; then
    log "AzureHound already present; skipping."
    return 0
  fi

  log "Installing AzureHound collector (BloodHound CE compatible) from GitHub releases..."
  require_cmd jq
  local ver
  ver="$(curl -s https://api.github.com/repos/SpecterOps/AzureHound/releases/latest | jq -r '.tag_name')"
  [[ -n "$ver" && "$ver" != "null" ]] || die "Could not determine AzureHound latest tag_name"

  local zip="/tmp/azurehound.zip"
  curl -sSL -o "$zip" "https://github.com/SpecterOps/AzureHound/releases/download/${ver}/AzureHound_${ver}_linux_amd64.zip"
  unzip -q "$zip" -d /tmp
  sudo mv /tmp/azurehound /usr/local/bin/azurehound
  sudo chmod 0755 /usr/local/bin/azurehound
  rm -f "$zip"
}

pipx_install() {
  local pkg="$1"
  if pipx list 2>/dev/null | grep -qE "package ${pkg}"; then
    log "pipx package already installed: ${pkg}"
    return 0
  fi
  log "pipx installing: ${pkg}"
  pipx install "${pkg}"
}

pipx_install_args() {
  # Use when the "package name" doesn't match pipx list grep cleanly (e.g. git+ URLs).
  local display="$1"
  shift
  if pipx list 2>/dev/null | grep -qiE "${display}"; then
    log "pipx package already installed (matched): ${display}"
    return 0
  fi
  log "pipx installing: ${display}"
  pipx install "$@"
}

install_pipx_tools() {
  log "Installing Azure and cloud tools via pipx (into ${PIPX_HOME})..."
  require_cmd pipx

  pipx_install "azure-cli"
  pipx_install "graphspy"
  pipx_install_args "ROADtools" "git+https://github.com/dirkjanm/ROADtools" --include-deps
  pipx_install_args "FindMeAccess" "git+https://github.com/absolomb/FindMeAccess" --include-deps
  pipx_install "impacket"
  pipx_install "seamlesspass"
  pipx_install "roadtx"
  pipx_install "prowler"
  pipx_install "scoutsuite"

  # Enable bash completion for az CLI (best-effort)
  if command -v az >/dev/null 2>&1; then
    log "Writing az bash completion to /etc/bash_completion.d/azure-cli (best-effort)..."
    sudo mkdir -p /etc/bash_completion.d
    az completion bash | sudo tee /etc/bash_completion.d/azure-cli >/dev/null || true
  else
    log "az not found on PATH; skipping az completion file."
  fi
}

clone_repos() {
  log "Cloning repositories into ${INSTALL_DIR} (depth=1)..."
  sudo mkdir -p "${INSTALL_DIR}"
  sudo chown -R "$(id -u)":"$(id -g)" "${INSTALL_DIR}"

  require_cmd git

  local entry url name dest
  for entry in "${REPOS[@]}"; do
    url="${entry%%|*}"
    name="${entry##*|}"
    dest="${INSTALL_DIR}/${name}"

    if [[ -d "${dest}/.git" ]]; then
      log "Repo already exists; skipping: ${name}"
      continue
    fi

    log "Cloning ${name}..."
    git clone --depth 1 "${url}" "${dest}"
  done
}

install_graphpython_system() {
  local gp="${INSTALL_DIR}/Graphpython"
  if [[ ! -d "$gp" ]]; then
    log "Graphpython directory not present; skipping system install."
    return 0
  fi

  log "Installing Graphpython into system Python (PEP 668: --break-system-packages)..."
  sudo -H python3 -m pip install --no-cache-dir --break-system-packages "$gp"
}

install_optional_requirements() {
  log "Installing optional Python requirements (TokenTacticsV2, MFASweep) if present..."
  local tt="${INSTALL_DIR}/TokenTacticsV2/requirements.txt"
  local mfa="${INSTALL_DIR}/MFASweep/requirements.txt"

  if [[ -f "$tt" ]]; then
    sudo -H python3 -m pip install --no-cache-dir --break-system-packages -r "$tt"
  fi
  if [[ -f "$mfa" ]]; then
    sudo -H python3 -m pip install --no-cache-dir --break-system-packages -r "$mfa"
  fi
}

download_exfil_script() {
  log "Downloading Exchange mail exfil script (best-effort)..."
  local d="${INSTALL_DIR}/exfil_exchange_mail"
  mkdir -p "$d"
  wget -O "${d}/exfil_exchange_mail.py" \
    "https://raw.githubusercontent.com/rootsecdev/Azure-Red-Team/master/exfil_exchange_mail.py" || true
}

install_evil_winrm() {
  if command -v evil-winrm >/dev/null 2>&1; then
    log "evil-winrm already present; skipping."
    return 0
  fi
  log "Installing evil-winrm Ruby gem..."
  sudo gem install evil-winrm
}

install_powershell_modules() {
  if ! command -v pwsh >/dev/null 2>&1; then
    log "pwsh not present; skipping PowerShell modules."
    return 0
  fi

  log "Installing PowerShell modules (AADInternals, Microsoft.Graph, Az) for AllUsers..."
  sudo pwsh -NoLogo -NoProfile -Command \
    "Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted; \
     Install-Module -Name AADInternals    -Force -Scope AllUsers; \
     Install-Module -Name Microsoft.Graph -Force -Scope AllUsers; \
     Install-Module -Name Az              -Force -Scope AllUsers"
}

install_starship() {
  if command -v starship >/dev/null 2>&1; then
    log "Starship already present; skipping install."
  else
    log "Installing Starship..."
    curl -sS https://starship.rs/install.sh | sudo sh -s -- -y
  fi

  # Copy starship.toml if present
  if [[ -f "$STARSHIP_SRC" ]]; then
    log "Copying starship.toml to ~/.config/starship.toml"
    mkdir -p "${HOME}/.config"
    install -m 0644 "$STARSHIP_SRC" "${HOME}/.config/starship.toml"
  else
    log "No starship.toml found at: ${STARSHIP_SRC} (skipping copy)"
  fi
}

configure_bashrc() {
  log "Configuring ~/.bashrc (idempotent block)..."
  local bashrc="${HOME}/.bashrc"
  local begin="# >>> pentest-tools >>>"
  local end="# <<< pentest-tools <<<"

  if grep -qF "$begin" "$bashrc" 2>/dev/null; then
    log "Bashrc block already present; skipping."
    return 0
  fi

  cat >>"$bashrc" <<'EOF'

# >>> pentest-tools >>>
# Enable bash completion (including az from /etc/bash_completion.d)
if [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# Ensure pipx /opt path is available in interactive shells (also set via /etc/profile.d)
export PIPX_HOME="/opt/pipx"
export PIPX_BIN_DIR="/opt/pipx/bin"
export PATH="/opt/pipx/bin:$PATH"

# Initialize Starship prompt for Bash (if installed)
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
fi

# Aliases for enhanced usability
alias cat="bat -p"        # Pretty cat using bat
alias ls="eza --icons"    # Enhanced ls with icons
# <<< pentest-tools <<<
EOF
}

sanity_checks() {
  [[ "$(id -u)" -ne 0 ]] || die "Do not run as root. Run as a normal user with sudo."
  require_cmd curl
  require_cmd sudo
}

main() {
  sanity_checks
  sudo_keepalive

  install_apt_packages
  setup_pipx_dirs
  setup_bat_shim

  install_powershell
  install_jwt_cli
  install_azurehound

  install_pipx_tools
  clone_repos

  install_graphpython_system
  install_optional_requirements
  download_exfil_script

  install_evil_winrm
  install_powershell_modules

  install_starship
  configure_bashrc

  log "Done."
  log "Open a new shell (or run: source /etc/profile.d/pentest-tools.sh) to pick up PATH changes."
}

main "$@"

