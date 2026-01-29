#!/usr/bin/env bash
set -euo pipefail

install_editors() {
  sudo pacman -S --noconfirm --needed \
    vulkan-radeon \
    zed
}

install_security() {
  sudo pacman -S --noconfirm --needed \
    keepassxc
}
install_office() {
  sudo pacman -S --noconfirm --needed \
    libreoffice-fresh \
    libreoffice-fresh-en-gb
}

install_cloud_tools() {
  sudo pacman -S --noconfirm --needed \
    kubectl \
    aws-cli-v2
}

install_network_tools() {
  sudo pacman -S --noconfirm --needed \
    nmap \
    wireshark-qt \
    wireshark-cli \
    rustnet
}

install_social() {
  sudo pacman -S --noconfirm --needed \
    discord
}

install_videoedit() {
  sudo pacman -S --noconfirm --needed \
    obs-studio \
    kdenlive
  sudo usermod -aG render $USER
}

install_virtualisation() {
  sudo pacman -S --noconfirm --needed \
    qemu-desktop \
    virt-manager \
    virt-viewer \
    spice-gtk \
    swtpm \
    dnsmasq
  sudo mkdir -p /etc/libvirt
  echo 'firewall_backend = "nftables"' | sudo tee /etc/libvirt/network.conf >/dev/null
  sudo usermod -aG libvirt,kvm $USER
  sudo systemctl enable libvirtd.service
}

install_docker() {
  sudo pacman -S --noconfirm --needed \
    docker \
    docker-compose \
    dive \
    lazydocker
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "firewall-backend": "nftables"
}
EOF
  sudo mkdir -p /etc/systemd/system/docker.service.d
  sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null <<EOF
[Unit]
After=nftables.service
Wants=nftables.service
EOF
  sudo usermod -aG docker $USER
  sudo systemctl enable docker.socket
  sudo systemctl enable docker.service
}

install_games() {
  sudo pacman -S --noconfirm --needed \
    lib32-vulkan-radeon \
    steam \
    jre-openjdk \
    prismlauncher
  yay -S --noconfirm --needed \
    heroic-games-launcher-bin
  if ! flatpak list | grep -q "com.hypixel.HytaleLauncher"; then
    mkdir -p ~/Downloads
    wget https://launcher.hytale.com/builds/release/linux/amd64/hytale-launcher-latest.flatpak -O ~/Downloads/hytale-launcher-latest.flatpak
    sudo flatpak install -y ~/Downloads/hytale-launcher-latest.flatpak
  fi
}

main() {
  install_editors
  install_office
  install_cloud_tools
  install_network_tools
  install_social
  install_videoedit
  install_virtualisation
  install_docker
  install_games
}

main "$@"
