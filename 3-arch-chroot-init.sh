#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

echo "${hostname}" > /etc/hostname
printf "127.0.0.1\tlocalhost\t${hostname}\n::1\tlocalhost\t${hostname}" >> /etc/hosts

safe-sed() {  # sed instructions should be idempotent!
  local sed_instruction="$1" file="$2"
  if [ -f "$file" ]; then
    sed -i "$sed_instruction" "$file"
  else
    echo "sed: file '$file' does not exist"
  fi
}

set -x

# sed -i 's/#\(Storage=\)auto/\1volatile/' /etc/systemd/journald.conf
safe-sed 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
safe-sed 's/#\(PermitRootLogin \).\+/\1yes/' /etc/ssh/sshd_config
safe-sed "s/#Server/Server/g" /etc/pacman.d/mirrorlist
safe-sed 's/#\(HandleSuspendKey=\)suspend/\1ignore/' /etc/systemd/logind.conf
safe-sed 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' /etc/systemd/logind.conf
safe-sed 's/#\(HandleLidSwitch=\)suspend/\1ignore/' /etc/systemd/logind.conf

safe-sed "s@\(^GRUB_CMDLINE_LINUX=\)\"\"@\1\"cryptdevice=${part_root}:cryptroot:allow-discards\"@" /etc/default/grub
safe-sed 's/#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /etc/default/grub

HOOKS="base udev autodetect keyboard modconf block encrypt filesystems resume fsck"
safe-sed "s/^HOOKS=(.*)/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf
safe-sed "s/^MODULES=()/MODULES=(ext4)/" /etc/mkinitcpio.conf

echo LANG=en_US.UTF-8 >> /etc/locale.conf
echo LANGUAGE=en_US >> /etc/locale.conf
echo LC_ALL=C >> /etc/locale.conf
export LANG='en_US.UTF-8'
locale-gen

ln -sf /usr/share/zoneinfo/US/Mountain /etc/localetime
hwclock --systohc --utc
timedatectl set-ntp true

useradd -mU -s /bin/bash -G audio,games,input,lp,network,power,root,storage,sys,uucp,video,wheel "$user"
chpasswd <<<"$user:$password"
chpasswd <<<"root:$password"

mkinitcpio -p linux
grub-install --boot-directory=/boot --efi-directory=/boot/efi "${part_boot}"
pacman -S --noconfirm intel-ucode # grub-mkconfig will automatically detect microcode updates and configure appropriately
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg