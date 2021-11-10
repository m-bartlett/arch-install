#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# Suspend to disk on LUKS https://gist.github.com/sjoqvist/9187974

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

pac-install() {
  pacman -S --noconfirm $@
}

safe-append() {
  local file="$1" content="$2"
  if [ -f "$file" ]; then
    if grep "$content" "$file" &>/dev/null ; then
      tee -a "$file" <<<"$content"
    else
      echo "safe-append: '$file' already contains '$content'" >&2
      return 1
    fi
  else
    echo "safe-append: '$file' does not exist" >&2
    return 1
  fi
}

set -x

# sed -i 's/#\(Storage=\)auto/\1volatile/' /etc/systemd/journald.conf
safe-sed 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
safe-sed 's/#\(PermitRootLogin \).\+/\1yes/' /etc/ssh/sshd_config
safe-sed "s/#Server/Server/g" /etc/pacman.d/mirrorlist
safe-sed 's/#\(HandleSuspendKey=\)suspend/\1ignore/' /etc/systemd/logind.conf
safe-sed 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' /etc/systemd/logind.conf
# safe-sed 's/#\(HandleLidSwitch=\)suspend/\1ignore/' /etc/systemd/logind.conf

# safe-sed "s@\(^GRUB_CMDLINE_LINUX=\)\"\"@\1\"cryptdevice=${part_root}:cryptroot:allow-discards\"@" /etc/default/grub
safe-sed \
  "s,^\(GRUB_CMDLINE_LINUX=\".*\)\"$,\1 splash cryptdevice=${part_root}:${cryptfsname} resume=${part_swap}\"," \
  /etc/default/grub

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
safe-append /etc/resolv.conf 'nameserver 192.168.0.51'$'\n''nameserver 8.8.8.8'

systemctl enable dhcpcd.service
pac-install ntp iw wpa_supplicant
systemctl enable ntpd
systemctl start ntpd

safe-append /etc/modprobe.d/i915.conf "options i915 i915_enable_rc6=7 i915_enable_fbc=1 lvds_downclock=1"
pac-install xorg-server xorg-server-utils xorg-xinit mesa xf86-video-intel
mkdir -p /etc/X11/xorg.conf.d/
cat << EOF > /etc/X11/xorg.conf.d/20-intel.conf
Section "Device"
  Identifier "Intel Graphics"
  Driver "intel"
  Option "TearFree" "true"
EndSection
EOF

pac-install xf86-input-libinput

useradd -mU -s /bin/bash -G audio,games,input,lp,network,power,root,storage,sys,uucp,video,wheel "$user"
chpasswd <<<"$user:$password"
chpasswd <<<"root:$password"
safe-sed "s/^# \(%wheel ALL=(ALL) ALL\)/\1/" /etc/sudoers
safe-append /etc/sudoers "$USER ALL=(ALL) NOPASSWD: ALL"


mkinitcpio -p linux
grub-install --boot-directory=/boot --efi-directory=/boot/efi "${part_boot}"
pac-install intel-ucode # grub-mkconfig will automatically detect microcode updates and configure appropriately
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg