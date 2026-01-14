#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-/dev/sda}"
MARKER="/mnt/.installed_by_repo_installer"
msg(){ echo -e "\n==> $*"; }
err(){ echo -e "\nERROR: $*" >&2; exit 1; }

if [ "$(id -u)" -ne 0 ]; then err "Run as root"; fi
if [ ! -b "$TARGET" ]; then err "Target device $TARGET not found."; fi

echo "Target device: $TARGET"
read -rp "This will wipe $TARGET. Type the device name to confirm: " CONF
if [ "$CONF" != "$TARGET" ]; then err "Confirmation mismatch."; fi

if [ -d /sys/firmware/efi ]; then FW=uefi; else FW=bios; fi

wipefs -a "$TARGET" || true
sgdisk -Zo "$TARGET"

if [ "$FW" = "uefi" ]; then
  sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" "$TARGET"
  sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux root" "$TARGET"
  PART_BOOT="${TARGET}1"; PART_ROOT="${TARGET}2"
else
  sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS boot" "$TARGET"
  sgdisk -n 2:0:0 -t 2:8300 -c 2:"Linux root" "$TARGET"
  PART_BOOT="${TARGET}1"; PART_ROOT="${TARGET}2"
fi

partprobe "$TARGET" || true
sleep 1; lsblk "$TARGET"

if [ "$FW" = "uefi" ]; then mkfs.fat -F32 "$PART_BOOT"; fi
mkfs.ext4 -F "$PART_ROOT"

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
if [ "$FW" = "uefi" ]; then mount "$PART_BOOT" /mnt/boot; fi

if [ -f "$MARKER" ]; then
  read -rp "Previous install exists. Remove? [y/N] " yn
  case "$yn" in [Yy]*) rm -f "$MARKER" ;; *) err "Aborted." ;; esac
fi

pacstrap /mnt base linux linux-firmware networkmanager sudo vim --noconfirm
genfstab -U /mnt >> /mnt/etc/fstab

read -rp "Hostname [arch]: " HOSTNAME; HOSTNAME=${HOSTNAME:-arch}
read -rp "Username [user]: " USERNAME; USERNAME=${USERNAME:-user}
read -rp "Timezone [Europe/Warsaw]: " TZ; TZ=${TZ:-Europe/Warsaw}

read -rsp "Root password: " ROOT_PASS; echo
read -rsp "Confirm root password: " ROOT_PASS2; echo
if [ "$ROOT_PASS" != "$ROOT_PASS2" ]; then echo "Passwords do not match. Aborting." >&2; exit 1; fi
read -rsp "Password for ${USERNAME}: " USER_PASS; echo
read -rsp "Confirm password for ${USERNAME}: " USER_PASS2; echo
if [ "$USER_PASS" != "$USER_PASS2" ]; then echo "User passwords do not match. Aborting." >&2; exit 1; fi

arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime
hwclock --systohc
echo "LANG=en_US.UTF-8" > /etc/locale.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen || true
locale-gen
echo "${HOSTNAME}" > /etc/hostname
useradd -m -G wheel -s /bin/bash "${USERNAME}" || true
systemctl enable NetworkManager
if ! grep -q "^%wheel" /etc/sudoers; then echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers; fi
EOF

printf "root:%s\n%s:%s\n" "$ROOT_PASS" "$USERNAME" "$USER_PASS" > /mnt/root/.pwfile
arch-chroot /mnt /usr/bin/chpasswd < /mnt/root/.pwfile
rm -f /mnt/root/.pwfile

if [ "$FW" = "uefi" ]; then
  arch-chroot /mnt /bin/bash -c "bootctl --path=/boot install"
  cat > /mnt/boot/loader/loader.conf <<LOADER
default arch
timeout 1
editor 0
LOADER

cat > /mnt/boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=${PART_ROOT} rw
ENTRY
else
  arch-chroot /mnt /bin/bash -lc "pacman -S --noconfirm grub"
  arch-chroot /mnt /bin/bash -lc "grub-install --target=i386-pc ${TARGET}"
  arch-chroot /mnt /bin/bash -lc "grub-mkconfig -o /boot/grub/grub.cfg"
fi

touch /mnt/.installed_by_repo_installer
sync
umount -R /mnt || true
msg "Installation finished. Remove ISO and reboot."

