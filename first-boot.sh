#!/usr/bin/env bash
set -euo pipefail

source ~/first-boot/.env

configure_pacman() {
  sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
  sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
}

configure_wifi() {
  local scan_timeout=30
  local scan_interval=3
  local i=0
  until iwctl station wlan0 get-networks | grep -q "$WIFI_SSID"; do
    iwctl station wlan0 scan
    sleep "$scan_interval"
    ((i += scan_interval))
    if ((i >= scan_timeout)); then
      echo "ERROR: SSID '$WIFI_SSID' not visible within ${scan_timeout}s" >&2
      return 1
    fi
  done
  iwctl --passphrase "$WIFI_PASS" station wlan0 connect "$WIFI_SSID"
  local timeout=15
  local i=0
  until ping -c1 -W1 archlinux.org >/dev/null 2>&1; do
    sleep 1
    ((++i))
    if ((i >= timeout)); then
      echo "ERROR: Wi-Fi did not come up within ${timeout}s" >&2
      return 1
    fi
  done
}

enable_systemd_dns() {
  sudo rm /etc/resolv.conf || true
  sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
}

enable_ssh() {
  sudo systemctl enable --now sshd.service
  sudo systemctl status sshd || true
}

update_system() {
  sudo pacman -Syu --noconfirm --needed
}

install_base_reqs() {
  sudo pacman -S --noconfirm --needed \
    base-devel \
    rust \
    git \
    github-cli
}

configure_firewall() {
  sudo tee /etc/nftables.conf >/dev/null <<EOF
table inet filter {
    chain prerouting {
        type filter hook prerouting priority raw - 10; policy accept;
        iifname { "br-*", "veth*" } accept comment "Container/bridge traffic before Docker raw"
    }
    chain input {
        type filter hook input priority filter - 10; policy drop;
        iif "lo" accept
        ct state established,related accept
        iifname "virbr*" accept comment "Trust all VM bridges"
        iifname "docker*" accept comment "Trust Docker default bridge"
        iifname "br-*" accept comment "Trust Docker custom bridges"
        tcp dport 22 accept comment "Allow SSH"
        tcp dport 9090 accept comment "Allow Cockpit Web Interface"
        tcp dport 53317 accept comment "Allow LocalSend (TCP)"
        udp dport 53317 accept comment "Allow LocalSend (UDP)"
        udp dport 53317 ip daddr 224.0.0.167 accept comment "Allow LocalSend Discovery"
        icmp type echo-request accept comment "Allow Ping"
    }
    chain forward {
        type filter hook forward priority filter - 10; policy drop;
        ct state established,related accept
        iifname { "wlan*", "en*" } oifname { "docker*", "br-*" } ct state new ct status dnat accept
        iifname "virbr*" accept
        iifname "docker*" accept
        iifname "br-*" accept
        iifname "veth*" accept
    }
}
table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "wlan*" masquerade
        oifname "en*" masquerade
    }
}
EOF
  sudo sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf >/dev/null
  sudo systemctl enable --now nftables
}

install_yay() {
  rm -rf ~/yay
  git clone https://aur.archlinux.org/yay.git ~/yay
  (cd ~/yay && makepkg -si --noconfirm)
  rm -rf ~/yay
  yay --version
}

install_niri_defaults() {
  sudo pacman -S --noconfirm --needed \
    alacritty \
    fuzzel \
    mako \
    niri \
    swaybg \
    swayidle \
    waybar \
    xdg-desktop-portal-gnome \
    xorg-xwayland \
    seatd \
    greetd \
    pipewire-jack
  sudo usermod -aG seat,video $USER
  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[initial_session]
command = "sh -c 'niri-session > /dev/null 2>&1'"
user = "$USER"

[default_session]
command = "agreety --cmd niri-session"
user = "greeter"
EOF
  sudo systemctl enable seatd.service
  sudo systemctl enable greetd.service
}

install_gui_extensions() {
  sudo pacman -S --noconfirm --needed \
    xwayland-satellite \
    xdg-desktop-portal-wlr \
    xdg-desktop-portal-gtk \
    gnome-keyring \
    libnotify \
    wl-clipboard \
    qt5-wayland \
    qt5ct \
    qt6-wayland \
    qt6ct \
    qt6-multimedia-ffmpeg \
    kvantum \
    kvantum-qt5 \
    hyprlock \
    hypridle \
    libappindicator \
    udiskie
  yay -S --noconfirm --needed \
    soteria-git
}

configure_niri_polkit_and_lock_services() {
  sudo chmod 4755 /usr/lib/polkit-1/polkit-agent-helper-1
  mkdir -p ~/.config/systemd/user
  cat >~/.config/systemd/user/soteria.service <<'EOF'
[Unit]
Description=Polkit authentication agent (soteria)
Requisite=graphical-session.target
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/lib/soteria-polkit/soteria
Restart=on-failure
RestartSec=2
ImportCredential=yes

[Install]
WantedBy=graphical-session.target
EOF
  cat >~/.config/systemd/user/hypridle.service <<'EOF'
[Unit]
Description=Idle Manager for Wayland
Requisite=graphical-session.target
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/hypridle
Restart=on-failure
RestartSec=1
TimeoutStopSec=5

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable soteria.service
  systemctl --user enable hypridle.service
}

set_darkmode() {
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' || true
  mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
  echo -e "[Settings]\ngtk-application-prefer-dark-theme=1" >~/.config/gtk-3.0/settings.ini
  echo -e "[Settings]\ngtk-application-prefer-dark-theme=1" >~/.config/gtk-4.0/settings.ini
}

install_fonts() {
  sudo pacman -S --noconfirm --needed \
    ttf-jetbrains-mono-nerd
  sudo mkdir -p /etc/fonts/conf.d/
  sudo ln -sf /usr/share/fontconfig/conf.avail/10-nerd-font-symbols.conf /etc/fonts/conf.d/
  sudo fc-cache -fv
}

set_wallpaper() {
  ln -s ~/Wallpaper/wallhaven-mpzgz1.jpg ~/.current_wallpaper
}

install_connectivity_tools() {
  sudo pacman -S --noconfirm --needed \
    bluetui \
    impala
  sudo systemctl enable --now bluetooth
}

install_sound_tools() {
  sudo pacman -S --noconfirm --needed \
    pavucontrol \
    pipewire-pulse \
    pulsemixer
}

install_disk_tools() {
  sudo pacman -S --noconfirm --needed \
    ntfs-3g \
    gvfs-smb \
    gvfs-nfs \
    dosfstools \
    exfat-utils
}

install_terminal_tools() {
  sudo pacman -S --noconfirm --needed \
    ghostty \
    bat \
    btop \
    chafa \
    eza \
    fastfetch \
    fzf \
    jq \
    less \
    mpv \
    neovim \
    ncdu \
    ripgrep \
    socat \
    tealdeer \
    wget \
    yazi \
    zip \
    unzip \
    7zip
  tldr --update
}

configure_shells() {
  sudo pacman -S --noconfirm --needed \
    starship
  cp -f ~/first-boot/shell_rc/.bashrc ~/.bashrc
}

configure_dotfiles() {
  sudo pacman -S --noconfirm --needed \
    rsync
  rsync -av ~/first-boot/config_files/ ~/.config/
}

configure_git() {
  git config --global user.email "$GIT_EMAIL"
  git config --global user.name "$GIT_USER"
  git config --global init.defaultBranch main
}

install_flatpak() {
  sudo pacman -S --noconfirm --needed \
    flatpak
}

configure_lazyvim() {
  rm -rf ~/.config/nvim
  rm -rf ~/.local/share/nvim
  rm -rf ~/.local/state/nvim
  rm -rf ~/.cache/nvim
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
}

install_browsers() {
  sudo pacman -S --noconfirm --needed \
    firefox
}

configure_tts() {
  sudo pacman -S --noconfirm --needed \
    speech-dispatcher
  yay -S --noconfirm --needed \
    piper-tts-bin \
    piper-voices-en-gb
  mkdir -p ~/.config/speech-dispatcher/modules
  cat >~/.config/speech-dispatcher/modules/piper-tts-generic.conf <<'EOF'
GenericExecuteSynth "export XDATA=\'$DATA\'; echo \"$XDATA\" | sed -z 's/\\n/ /g' | piper-tts -q -m \"/usr/share/piper-voices/en/en_GB/cori/high/en_GB-cori-high.onnx\" -f - | pw-play -"

AddVoice "en-GB" "FEMALE1" "en_GB-cori-high"
DefaultVoice "en_GB-cori-high"
EOF
  cat >~/.config/speech-dispatcher/speechd.conf <<'EOF'
LogLevel  3
LogDir  "default"
DefaultRate   0
DefaultPitch   0
DefaultPitchRange   0
DefaultVolume 100
DefaultLanguage   "en-GB"
SymbolsPreproc "char"
SymbolsPreprocFile "gender-neutral.dic"
SymbolsPreprocFile "font-variants.dic"
SymbolsPreprocFile "symbols.dic"
SymbolsPreprocFile "emojis.dic"
SymbolsPreprocFile "orca.dic"
SymbolsPreprocFile "orca-chars.dic"
AudioOutputMethod   pulse
AddModule "piper-tts-generic" "sd_generic" "piper-tts-generic.conf"
DefaultModule  "piper-tts-generic"
Include "clients/*.conf"
EOF
  systemctl --user restart speech-dispatcher.service 2>/dev/null || true
}

enable_secureboot() {
  sudo sbctl create-keys
  sudo sbctl enroll-keys -m
  sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
  sudo sbctl sign -s /boot/EFI/Linux/arch-linux-zen.efi
  sudo sbctl sign -s /boot/EFI/Linux/arch-linux-zen-fallback.efi
  sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
  sudo sbctl sign -s /boot/vmlinuz-linux-zen
  sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
  sudo sbctl verify
}

configure_snapshots() {
  sudo pacman -S --noconfirm --needed \
    snapper snap-pac
  sudo umount /home/.snapshots
  sudo umount /.snapshots
  sudo rmdir /.snapshots
  sudo rmdir /home/.snapshots
  sudo snapper -c root create-config /
  sudo snapper -c home create-config /home
  sudo sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' /etc/snapper/configs/home
  sudo btrfs subvolume delete /.snapshots
  sudo btrfs subvolume delete /home/.snapshots
  sudo mkdir -p /.snapshots
  sudo mkdir -p /home/.snapshots
  sudo mount /.snapshots
  sudo mount /home/.snapshots
  sudo systemctl enable --now snapper-timeline.timer
  sudo systemctl enable --now snapper-cleanup.timer
  sudo snapper -c root create -d "initial root snapshot"
  sudo snapper -c home create -d "initial home snapshot"
}

main() {

  clear
  CYAN='\033[0;36m'
  YELLOW='\033[1;33m'
  BOLD='\033[1m'
  NC='\033[0m' # No Color
  echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
  echo -e "${CYAN}┃${NC}        ${BOLD}ZBOOK ARCH LINUX INSTALLER${NC}          ${CYAN}┃${NC}"
  echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
  echo
  echo -e " ${YELLOW}󰌾${NC} ${BOLD}SUDO PRIVILEGES REQUIRED${NC}"
  echo -e " This script will configure your system hardware,"
  echo -e " encryption, and security policies."
  echo
  echo -e " Please enter your password to begin:"
  if sudo -v; then
    echo -e "\n ${CYAN}✓${NC} Authenticated. Starting installation..."
    sleep 2
  else
    echo -e "\n ${BOLD}Authentication failed. Exiting.${NC}"
    exit 1
  fi

  echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/first-boot-privs >/dev/null
  mkdir -p ~/.config

  configure_pacman
  configure_wifi
  enable_systemd_dns
  enable_ssh
  update_system
  install_base_reqs
  configure_firewall
  install_yay
  install_niri_defaults
  install_gui_extensions
  configure_niri_polkit_and_lock_services
  set_darkmode
  install_fonts
  set_wallpaper
  install_connectivity_tools
  install_sound_tools
  install_disk_tools
  install_terminal_tools
  configure_shells
  configure_dotfiles
  configure_git
  install_flatpak
  configure_lazyvim
  install_browsers
  configure_tts
  enable_secureboot
  configure_snapshots

  sudo rm /etc/sudoers.d/first-boot-privs
  rm ~/first-boot/.env

  clear
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
  echo -e "${BLUE}==============================================${NC}"
  echo -e "${BOLD}       INSTALLATION COMPLETE${NC}"
  echo -e "${BLUE}==============================================${NC}"
  echo
  echo -e " ${BOLD}ACTION REQUIRED:${NC}"
  echo -e " Please enter your BIOS/UEFI settings and"
  echo -e " ${BLUE}ENABLE SECURE BOOT${NC} before the next start."
  echo
  echo -e "${BLUE}----------------------------------------------${NC}"
  echo -e " Press ${BOLD}[ENTER]${NC} to power off..."
  read -r

  poweroff

}

main "$@"
