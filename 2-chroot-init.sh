#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

# Special thanks to https://gist.github.com/m4jrt0m/2125d5ad87fad7216a8e7591337709cf

# Suspend to disk on LUKS https://gist.github.com/sjoqvist/9187974

safe-sed() {  # sed instructions should be idempotent!
  local sed_instruction="$1" file="$2"
  if [ -f "$file" ]; then
    sed -i "$sed_instruction" "$file"
  else
    echo "sed: file '$file' does not exist"
  fi
}

safe-append() {
  local file="$1" content="$2"
  local append=0
  if [ -f "$file" ]; then
    if ! grep "$content" "$file" &>/dev/null ; then
      append=1
    else
      echo "safe-append: '$file' already contains '$content'" >&2
    fi
  else
    mkdir -p "$(dirname "$file")"
    touch "$file"
    append=1
  fi
  if ((append)); then
    tee -a "$file" <<<"$content"
    echo "Added '$content' to '$file'"
  fi
}

pacman_packages=(
  ntp
  iw
  wpa_supplicant
  dhcpcd
  networkmanager
  network-manager-applet
  wget
  curl
  nm-connection-editor

  bluez
  bluez-utils
  blueman

  tlp
  tlp-rdw
  powertop
  lshw
  acpi

  pulseaudio
  alsa-utils
  alsa-plugins
  pulseaudio-alsa
  pulseaudio-bluetooth
  pipewire
  pavucontrol

  mesa
  vulkan-intel
  xclip
  xdg-user-dirs
  xdotool
  xf86-input-libinput
  xf86-video-intel
  xorg-xdpyinfo
  xorg-server
  xorg-xinit
  xorg-xinput
  xorg-xset
  xorg-xrandr

  i3-gaps
  i3lock
  lightdm
  lightdm-gtk-greeter
  lxappearance
  papirus-icon-theme
  arc-gtk-theme

  intel-ucode # grub-mkconfig will automatically detect microcode updates and configure appropriately

  autorandr
  cmake
  dmenu
  dunst
  entr
  epdfview
  exiv2
  ffmpeg
  fzf
  gparted
  hexchat
  htop
  jq
  mpv
  noto-fonts
  pcmanfm
  picom
  playerctl
  python-i3ipc
  python-numpy
  python-pip
  redshift
  rofi
  scrot
  strace
  telegram-desktop
  ttf-dejavu ttf-freefont
  ttf-droid
  ttf-joypixels
  ttf-liberation
  ttf-roboto
  terminus-font
  ttf-ubuntu-font-family
  unzip
  w3m
  which
)

pacman -Sy
pacman -S --noconfirm reflector
reflector --latest 5 --sort rate --save /etc/pacman.d/mirrorlist

pacman -S --noconfirm --needed ${pacman_packages[@]}

set -x

echo "${hostname}" > /etc/hostname
safe-append /etc/hosts '127.0.0.1'$'\t''localhost'$'\t'"${hostname}"$'\n''::1'$'\t''localhost'$'\t'"${hostname}"


# sed -i 's/#\(Storage=\)auto/\1volatile/' /etc/systemd/journald.conf
safe-sed 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
safe-sed 's/#\(PermitRootLogin \).\+/\1yes/' /etc/ssh/sshd_config
safe-sed "s/#Server/Server/g" /etc/pacman.d/mirrorlist
safe-sed 's/#\(HandleSuspendKey=\)suspend/\1ignore/' /etc/systemd/logind.conf
safe-sed 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' /etc/systemd/logind.conf
safe-sed 's/#\(Color\)/\1/' /etc/pacman.conf
# safe-sed 's/#\(HandleLidSwitch=\)suspend/\1ignore/' /etc/systemd/logind.conf

HOOKS="base udev autodetect keyboard modconf block encrypt filesystems resume fsck"
safe-sed "s/^HOOKS=(.*)/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf
safe-sed "s/^MODULES=()/MODULES=(ext4)/" /etc/mkinitcpio.conf

export LANG='en_US.UTF-8'
touch /etc/vconsole.conf
safe-append /etc/vconsole.conf 'KEYMAP=us'
touch /etc/locale.conf
safe-append /etc/locale.conf   'LANG=en_US.UTF-8'
safe-append /etc/locale.conf   'LANGUAGE=en_US'
safe-append /etc/locale.conf   'LC_ALL=C'
locale-gen

ln -sf /usr/share/zoneinfo/US/Mountain /etc/localetime
hwclock --systohc --utc
timedatectl set-ntp true
safe-append /etc/resolv.conf 'nameserver 192.168.0.51'$'\n''nameserver 8.8.8.8'
safe-append etc/wpa_supplicant/wpa_supplicant.conf 'ctrl_interface=/run/wpa_supplicant'$'\n''update_config=1'

systemctl enable ntpd
systemctl start ntpd
systemctl enable sshd
systemctl enable dhcpcd
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable tlp
# systemctl enable tlp-sleep
systemctl mask systemd-rfkill.service
systemctl mask systemd-rfkill.socket
systemctl enable lightdm
# sudo systemctl enable fstrim.timer


safe-append /etc/modprobe.d/i915.conf "options i915 i915_enable_rc6=7 i915_enable_fbc=1 lvds_downclock=1"
mkdir -p /etc/X11/xorg.conf.d/
cat << EOF > /etc/X11/xorg.conf.d/20-intel.conf
Section "Device"
  Identifier "Intel Graphics"
  Driver "intel"
  Option "TearFree" "true"
EndSection
EOF

safe-sed 's/#\(theme-name=\)/\1Arc-Dark/' /etc/lightdm/lightdm-gtk-greeter.conf
safe-sed 's/#\(icon-theme-name=\)/\1Papirus-Dark/' /etc/lightdm/lightdm-gtk-greeter.conf
safe-sed 's,#\(background=\),\1/boot/grub/themes/arch/bg.png,' /etc/lightdm/lightdm-gtk-greeter.conf

useradd -mU -s /bin/bash -G audio,games,input,lp,network,power,root,storage,sys,uucp,video,wheel "$user"
chpasswd <<<"$user:$password"
chpasswd <<<"root:$password"
safe-sed "s/^# \(%wheel ALL=(ALL) ALL\)/\1/" /etc/sudoers
safe-append /etc/sudoers "$user ALL=(ALL) NOPASSWD: ALL"

export GIT_SSH_COMMAND="ssh -i /id_rsa -o 'StrictHostKeyChecking=no'"
git clone git@gitlab.com:mbartlet/dot.git /.,
chown -R "$user": /., /usr/local/bin

su --login "$user" /user-init.sh

## Custome grub theme
mkdir -p /boot/grub/themes
cp -r "/grub" /boot/grub/themes/arch
safe-sed \
  "s,^\(GRUB_CMDLINE_LINUX=\".*\)\"$,\1 splash cryptdevice=${part_root}:${cryptfsname} resume=${part_swap}\"," \
  /etc/default/grub
safe-sed 's/#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /etc/default/grub
safe-sed 's/^#\(GRUB_THEME=".*"\)/\1/' /etc/default/grub
safe-sed 's,^\(GRUB_THEME=\)".*",\1"/boot/grub/themes/arch/theme.txt",' /etc/default/grub
[ -d /boot/grub/themes/starfield ] && rm -rf /boot/grub/themes/starfield

mkinitcpio -p linux
grub-install --boot-directory=/boot --efi-directory=/boot/efi "${part_boot}"
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg
