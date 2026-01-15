#!/usr/bin/env bash
set -euo pipefail
set -x

export LUKS_PASSPHRASE="strixhalo.boot"
export ROOT_PASS="archroot.btw"
export USER_NAME="joe"
export USER_PASS="arch.btw"
export WIFI_SSID="EE-X7F2N3"
export WIFI_PASS="MkNvLpfKb4hrpa"
export RAM_GB=32

configure_live_environment() {
  loadkeys uk
  iwctl --passphrase "$WIFI_PASS" station wlan0 connect "$WIFI_SSID"
}

enable_ssh() {
  echo "root:$ROOT_PASS" | chpasswd
  systemctl start sshd
}

clear_and_partition_drive() {
  wipefs -a /dev/nvme0n1
  sgdisk --zap-all /dev/nvme0n1
  partprobe /dev/nvme0n1
  sgdisk \
    --new=1:0:+512M --typecode=1:ef00 --change-name=1:EFI \
    --new=2:0:0 --typecode=2:8309 --change-name=2:cryptroot \
    /dev/nvme0n1
  partprobe /dev/nvme0n1
  udevadm settle
}

create_and_open_LUKS() {
  printf '%s' "$LUKS_PASSPHRASE" | cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --key-file - \
    /dev/nvme0n1p2
  printf '%s' "$LUKS_PASSPHRASE" | cryptsetup open \
    /dev/nvme0n1p2 cryptroot --key-file -
  unset LUKS_PASSPHRASE
}

format_partitions() {
  mkfs.fat -F32 -n EFI /dev/nvme0n1p1
  mkfs.btrfs -L arch /dev/mapper/cryptroot
  mount /dev/mapper/cryptroot /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  btrfs subvolume create /mnt/@log
  btrfs subvolume create /mnt/@cache
  btrfs subvolume create /mnt/@pkg
  btrfs subvolume create /mnt/@swap
  btrfs subvolume create /mnt/@snapshots.root
  btrfs subvolume create /mnt/@snapshots.home
  umount /mnt
}

mount_partitions() {
  mount -o compress=zstd,noatime,ssd,subvol=@ /dev/mapper/cryptroot /mnt
  mkdir -p /mnt/boot
  mkdir -p /mnt/home
  mkdir -p /mnt/var/log
  mkdir -p /mnt/var/cache
  mkdir -p /mnt/.snapshots
  mkdir -p /mnt/.swap
  mount -o compress=zstd,noatime,ssd,subvol=@home \
    /dev/mapper/cryptroot /mnt/home
  mount -o compress=zstd,noatime,ssd,subvol=@log \
    /dev/mapper/cryptroot /mnt/var/log
  mount -o compress=zstd,noatime,ssd,subvol=@cache \
    /dev/mapper/cryptroot /mnt/var/cache
  mkdir -p /mnt/var/cache/pacman/pkg
  mount -o compress=zstd,noatime,ssd,subvol=@pkg \
    /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
  mount -o noatime,ssd,subvol=@swap \
    /dev/mapper/cryptroot /mnt/.swap
  mount -o compress=zstd,noatime,ssd,subvol=@snapshots.root \
    /dev/mapper/cryptroot /mnt/.snapshots
  mkdir -p /mnt/home/.snapshots
  mount -o compress=zstd,noatime,ssd,subvol=@snapshots.home \
    /dev/mapper/cryptroot /mnt/home/.snapshots
  mount /dev/nvme0n1p1 /mnt/boot
}

configure_swap() {
  SWAP_GB=$(( (RAM_GB * 3 + 1) / 2 ))
  chattr +C /mnt/.swap
  btrfs filesystem mkswapfile --size "${SWAP_GB}G" --uuid clear /mnt/.swap/swapfile
  swapon /mnt/.swap/swapfile
}

pacstrap_base() {
  mkdir -p /mnt/etc
  echo "KEYMAP=uk" >/mnt/etc/vconsole.conf
  pacstrap -K /mnt \
    base \
    linux-zen \
    linux-firmware \
    amd-ucode \
    efibootmgr \
    btrfs-progs \
    cryptsetup \
    plymouth \
    iwd \
    openssh \
    sudo \
    vim
}

configure_fstab() {
  genfstab -U /mnt >/mnt/etc/fstab
  sed -i 's/fmask=0022,dmask=0022/fmask=0077,dmask=0077/g' /mnt/etc/fstab
}

chroot_config() {
  mkdir -p /mnt/tmp
  cat >/mnt/tmp/pw <<EOF
ROOT_PASS="$ROOT_PASS"
USER_NAME="$USER_NAME"
USER_PASS="$USER_PASS"
RAM_GB="$RAM_GB"
EOF
  arch-chroot /mnt /bin/bash <<'CHROOT'
source /tmp/pw
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
sed -i 's/^#\s*\(en_GB.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
echo "KEYMAP=uk" > /etc/vconsole.conf
echo "zbookai" > /etc/hostname
cat > /etc/hosts <<'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   zbookai.localdomain zbookai
EOF
sed -i 's/^#\s*\(MulticastDNS=yes\)/\1/' /etc/systemd/resolved.conf
mkdir -p /etc/iwd
cat > /etc/iwd/main.conf <<'EOF'
[General]
EnableNetworkConfiguration=false
AutoConnect=true

[Network]
NameResolvingService=systemd
EOF
cat > /etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
MulticastDNS=yes

[DHCPv4]
UseHostname=true
EOF
cat > /etc/systemd/network/25-wireless.network <<'EOF'
[Match]
Name=wl*

[Network]
DHCP=yes
MulticastDNS=yes

[DHCPv4]
UseHostname=true
EOF
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable iwd
systemctl enable fstrim.timer
sed -i 's/^MODULES=().*/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
sed -i 's|^HOOKS=(.*)|HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole plymouth block sd-encrypt filesystems resume)|' /etc/mkinitcpio.conf
bootctl install
cat > /boot/loader/loader.conf <<'EOF'
default arch
timeout 0
editor no
EOF
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) && \
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot) && \
RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /.swap/swapfile) && \
mkdir -p /boot/loader/entries && \
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux (zen)
linux   /vmlinuz-linux-zen
initrd  /amd-ucode.img
initrd  /initramfs-linux-zen.img
options rd.luks.name=${LUKS_UUID}=cryptroot rd.luks.options=discard root=/dev/mapper/cryptroot rootfstype=btrfs rootflags=subvol=@ rw quiet splash resume=UUID=${ROOT_UUID} resume_offset=${RESUME_OFFSET} vt.global_cursor_default=0
EOF
echo "options amdgpu runpm=0" > /etc/modprobe.d/amdgpu.conf
sed -i 's/^#\s*\(%wheel ALL=(ALL:ALL) ALL\)/\1/' /etc/sudoers
IMAGE_SIZE_BYTES=$(( (RAM_GB - 1) * 1024 * 1024 * 1024 ))
mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/hibernation-image-size.conf <<EOF
w /sys/power/image_size - - - - ${IMAGE_SIZE_BYTES}
EOF
plymouth-set-default-theme -R bgrt
echo "root:$ROOT_PASS" | chpasswd
useradd -m -G wheel "$USER_NAME"
echo "$USER_NAME:$USER_PASS" | chpasswd
exit
CHROOT
}

copy_firstboot_script() {
  mkdir -p /mnt/home/$USER_NAME/first-boot/
  cp scripts/first-boot.sh /mnt/home/$USER_NAME/first-boot/first-boot.sh
  cp -r config_files /mnt/home/$USER_NAME/first-boot/
  cp -r shell_rc /mnt/home/$USER_NAME/first-boot/
  chown -R 1000:1000 /mnt/home/$USER_NAME/first-boot
  chmod +x /mnt/home/$USER_NAME/first-boot/first-boot.sh
}

copy_wallpaper() {
  cp -r Wallpaper /mnt/home/$USER_NAME/
  chown -R 1000:1000 /mnt/home/$USER_NAME/Wallpaper
}

copy_firefox_config() {
  cp scripts/unfuck-firefox.sh /mnt/home/$USER_NAME/unfuck-firefox.sh
  chown 1000:1000 /mnt/home/$USER_NAME/unfuck-firefox.sh
  chmod +x /mnt/home/$USER_NAME/unfuck-firefox.sh
}

unmount_and_close_LUKS() {
  swapoff /mnt/.swap/swapfile
  umount -R /mnt
  cryptsetup close cryptroot
}

pause() {
  #read -p $'\nPress [Enter] to continue to the next step...\n'
  echo "Done"
}

main() {
  configure_live_environment
  pause
  #enable_ssh; pause
  clear_and_partition_drive
  pause
  create_and_open_LUKS
  pause
  format_partitions
  pause
  mount_partitions
  pause
  configure_swap
  pause
  pacstrap_base
  pause
  configure_fstab
  pause
  chroot_config
  pause
  copy_firstboot_script
  pause
  copy_wallpaper
  pause
  copy_firefox_config
  pause
  unmount_and_close_LUKS
  read -rp $'Press Enter to reboot…'
  reboot
}

main "$@"
