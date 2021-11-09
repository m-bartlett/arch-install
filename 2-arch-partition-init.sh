#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

read -p "Enter hostname: " hostname
: ${hostname:?"hostname cannot be empty"}

read -p "Enter primary user username: " user
: ${user:?"user cannot be empty"}

while : ; do
  read -p "Enter admin password: " password
  printf '\e[1F\e[2K'
  if [ -z "$password" ]; then
    echo "password cannot be empty"
    continue
  fi

  read -p "Enter admin password again: " password2
  printf '\e[1F\e[2K'
  if [[ "$password" == "$password2" ]]; then
    break
  else
    echo "Passwords did not match"
  fi
done

while : ; do
  devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
  echo "Select drive device to install Arch onto:"
  device="$(
    IFS=$'\n'
    select device in $devicelist; do echo $device; break; done \
    | cut -d' ' -f1
  )"
  if [ -n "$device" ]; then
    break
  else
    echo "Invalid device selected"
    echo
  fi
done


read -p "Enter name for encrypted filesystem [cryptroot]: " cryptfsname
cryptfsname="${cryptfsname:-cryptroot}"

clear
cat <<EOF
hostname  = $hostname
username  = $user
device    = $device
luks name = $cryptfsname

EOF

read -p "Continue? [y/N]: " input
echo
if [ "${input,,}" != "y" ]; then
  echo "Quitting..."
  exit 1
fi


set -x

#### Partitioning
## A separate, unencrypted boot partition is needed for disk encryption

swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB

sgdisk -Z "${device}"

# Make boot, swap, and root
parted \
  --script "${device}" \
  -- \
    mklabel gpt \
    mkpart ESP fat32 1Mib 129MiB \
    set 1 boot on \
    mkpart primary linux-swap 129MiB ${swap_end} \
    mkpart primary ext4 ${swap_end} 100%



### Setup the disk and partitions ###

part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 -n "EFI" "${part_boot}"



#### Encrypted root

modprobe dm-crypt
modprobe dm-mod
cryptsetup -y -v luksFormat -s 512 -h sha512 "${part_root}"
cryptsetup open "${part_root}" ${cryptfsname}
mkfs.ext4 -L root /dev/mapper/${cryptfsname}



#### Init boot and swap

mkswap "${part_swap}"
swapon "${part_swap}"

mount /dev/mapper/${cryptfsname} /mnt
mkdir -p /mnt/boot/efi
mount "${part_boot}" /mnt/boot/efi

# genfstab -U /mnt > /mnt/etc/fstab
mkdir /mnt/etc
genfstab -t PARTUUID /mnt > /mnt/etc/fstab

echo "${hostname}" > /mnt/etc/hostname
printf "127.0.0.1\tlocalhost\t${hostname}\n::1\tlocalhost\t${hostname}" >> /etc/hosts

pacstrap /mnt base base-devel efibootmgr grub linux linux-firmware




#### Init installed root

sed -i 's/#\(en_US\.UTF-8\)/\1/' /mnt/etc/locale.gen
# sed -i 's/#\(PermitRootLogin \).\+/\1yes/' /mnt/etc/ssh/sshd_config
sed -i "s/#Server/Server/g" /mnt/etc/pacman.d/mirrorlist
# sed -i 's/#\(Storage=\)auto/\1volatile/' /mnt/etc/systemd/journald.conf
sed -i 's/#\(HandleSuspendKey=\)suspend/\1ignore/' /mnt/etc/systemd/logind.conf
sed -i 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' /mnt/etc/systemd/logind.conf
sed -i 's/#\(HandleLidSwitch=\)suspend/\1ignore/' /mnt/etc/systemd/logind.conf

sed -i 's@\(^GRUB_CMDLINE_LINUX=\)""@\1"cryptdevice=/dev/sda3:cryptroot:allow-discards"@' /mnt/etc/default/grub
sed -i -E -e 's/(^HOOKS=\(.*) filesystems/\1 encrypt filesystems/' /mnt/etc/mkinitcpio.conf
echo LANG=en_US.UTF-8 > /mnt/etc/locale.genconf
# export LANG='en_US.UTF-8'

arch-chroot /mnt useradd -mU -s /bin/bash -G audio,games,input,lp,network,power,root,storage,sys,uucp,video,wheel "$user"
echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt
arch-chroot /mnt  locale-gen
arch-chroot /mnt  ln -sf /usr/share/zoneinfo/US/Mountain /etc/localetime
arch-chroot /mnt  hwclock --systohc --utc
arch-chroot /mnt  timedatectl set-ntp true
arch-chroot /mnt  mkinitcpio -p linux
arch-chroot /mnt  grub-install --boot-directory=/boot --efi-directory=/boot/efi "${part_boot}"
arch-chroot /mnt  grub-mkconfig -o /boot/grub/grub.cfg
arch-chroot /mnt  grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg

clear
echo "Done!"
