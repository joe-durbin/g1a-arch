#!/usr/bin/env bash
WIFI_SSID="EE-X7F2N3"
WIFI_PASSWORD="MkNvLpfKb4hrpa"

set -euo pipefail

configure_wifi() {
  iwctl --passphrase "$WIFI_PASSWORD" station wlan0 connect "$WIFI_SSID"
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
    git
}

install_niri_defaults() {
  sudo pacman -S --noconfirm --needed \
    alacritty \
    fuzzel \
    mako \
    niri \
    swaybg \
    swayidle \
    swaylock \
    waybar \
    xdg-desktop-portal-gnome \
    xorg-xwayland \
    seatd \
    greetd \
    pipewire-jack
  sudo usermod -aG seat $USER
  sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "sh -c 'niri-session > /dev/null 2>&1'"
user = "$USER"
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
    kvantum \
    kvantum-qt5 \
    hyprlock \
    hypridle \
    hyprpolkitagent
}

configure_niri_polkit_and_lock_services() {
  mkdir -p ~/.config/systemd/user
  cat >~/.config/systemd/user/polkit-agent.service <<'EOF'
[Unit]
Description=Polkit authentication agent (hyprpolkitagent)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/lib/hyprpolkitagent/hyprpolkitagent
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
EOF
  cat >~/.config/systemd/user/hypridle.service <<'EOF'
[Unit]
Description=Hypridle
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/hypridle
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable polkit-agent.service
  systemctl --user enable hypridle.service
}

install_fonts() {
  sudo pacman -S --noconfirm --needed \
    ttf-jetbrains-mono-nerd
  sudo mkdir -p /etc/fonts/conf.d/
  sudo ln -sf /usr/share/fontconfig/conf.avail/10-nerd-font-symbols.conf /etc/fonts/conf.d/
  sudo fc-cache -fv
}

set_wallpaper() {
  ln -s ~/Wallpaper/wallhaven-dp19wl.jpg ~/.current_wallpaper
}

install_yay() {
  rm -rf ~/yay
  git clone https://aur.archlinux.org/yay.git ~/yay
  (cd ~/yay && makepkg -si --noconfirm)
  rm -rf ~/yay
  yay --version
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
    dosfstools
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
    ncdu \
    ripgrep \
    socat \
    wget \
    yazi \
    zip
}

install_flatpak() {
  sudo pacman -S --noconfirm --needed \
    flatpak
}

install_editors() {
  sudo pacman -S --noconfirm --needed \
    vulkan-radeon \
    zed \
    neovim
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

install_cloud_tools() {
  sudo pacman -S --noconfirm --needed \
    kubectl \
    aws-cli-v2
}

install_network_tools() {
  sudo pacman -S --noconfirm --needed \
    nmap \
    qt6-multimedia-ffmpeg \
    wireshark-qt \
    wireshark-cli
}

install_social() {
  sudo pacman -S --noconfirm --needed \
    discord
}

install_games() {
  sudo pacman -S --noconfirm --needed \
    jre-openjdk \
    prismlauncher
}

configure_shells() {
  sudo pacman -S --noconfirm --needed \
    starship
  cp -f shell_rc/.bashrc ~/.bashrc
}

configure_dotfiles() {
  sudo pacman -S --noconfirm --needed \
    rsync
  rsync -av config_files/ ~/.config/
}

configure_firewall() {
  sudo pacman -S --noconfirm --needed \
    ufw
  sudo ufw --force reset
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw --force enable
  sudo systemctl enable --now ufw
  sudo ufw status
}

set_darkmode() {
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' || true
  mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
  echo -e "[Settings]\ngtk-application-prefer-dark-theme=1" >~/.config/gtk-3.0/settings.ini
  echo -e "[Settings]\ngtk-application-prefer-dark-theme=1" >~/.config/gtk-4.0/settings.ini
}

fix_mouse() {
  sudo pacman -S --noconfirm --needed \
    solaar
  solaar config "MX Master 3S" hires-smooth-resolution False
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

pause() {
  #read -p $'\nPress [Enter] to continue to the next step...\ni'
  echo done
}

main() {
  mkdir -p ~/.config
  configure_wifi
  pause
  enable_systemd_dns
  pause
  #enable_ssh; pause
  update_system
  pause
  install_base_reqs
  pause
  install_yay
  pause
  set_wallpaper
  pause
  install_niri_defaults
  pause
  install_gui_extensions
  pause
  configure_niri_polkit_and_lock_services
  pause
  install_fonts
  pause
  install_connectivity_tools
  pause
  install_sound_tools
  pause
  install_disk_tools
  pause
  install_terminal_tools
  pause
  install_editors
  pause
  install_flatpak
  pause
  configure_lazyvim
  pause
  install_browsers
  pause
  install_cloud_tools
  pause
  install_network_tools
  pause
  install_social
  pause
  install_games
  pause
  configure_shells
  pause
  configure_dotfiles
  pause
  configure_firewall
  pause
  set_darkmode
  pause
  fix_mouse
  pause
  configure_snapshots
  pause
  echo "Completed. Please reboot"
}

main "$@"
