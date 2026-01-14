#!/usr/bin/env bash
set -e

DISK="/dev/sda"
HOSTNAME="arch"
USERNAME="Marcin"
TIMEZONE="Europe/Warsaw"

echo "instalowanie do $DISK"
sleep 2

# wipe disk
wipefs -af "$DISK"
sgdisk -Zo "$DISK"

# partition
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
sgdisk -n 2:0:0     -t 2:8300 "$DISK"

# format
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 "${DISK}2"

# mount
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# base install
pacstrap /mnt base linux linux-firmware sudo networkmanager

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$HOSTNAME" > /etc/hostname

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

systemctl enable NetworkManager

bootctl install
cat <<BOOT > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=${DISK}2 rw
BOOT
EOF

echo "DONE. Reboot."
