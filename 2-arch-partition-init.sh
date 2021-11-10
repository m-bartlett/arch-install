#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

BASH_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  read -p "Enter LUKS crypt passphrase: " cryptpassphrase
  printf '\e[1F\e[2K'
  if [ -z "$cryptpassphrase" ]; then
    echo "Crypt passphrase cannot be empty"
    continue
  fi

  read -p "Enter LUKS crypt passphrase again: " cryptpassphrase2
  printf '\e[1F\e[2K'
  if [[ "$cryptpassphrase" == "$cryptpassphrase2" ]]; then
    break
  else
    echo "Crypt passphrase did not match"
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

export hostname user password device cryptfsname


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

export part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
export part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
export part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 -n "EFI" "${part_boot}"



#### Encrypted root

modprobe dm-crypt
modprobe dm-mod
cryptsetup -y -v luksFormat -s 512 -h sha512 "${part_root}" <<<"$cryptpassphrase"$'\n'"$cryptpassphrase"
cryptsetup open "${part_root}" ${cryptfsname} <<<"$cryptpassphrase"
mkfs.ext4 -L root /dev/mapper/${cryptfsname}



#### Init boot and swap

mkswap "${part_swap}"
swapon "${part_swap}"

mount /dev/mapper/${cryptfsname} /mnt
mkdir -p /mnt/boot/efi
mkdir /mnt/etc
mount "${part_boot}" /mnt/boot/efi

pacstrap /mnt base base-devel efibootmgr grub linux linux-firmware

genfstab -pU /mnt >> /mnt/etc/fstab

cp -v $BASH_SOURCE_DIR/3-*.sh /mnt/arch-init.sh
arch-chroot /mnt /arch-init.sh


clear
echo "Done!"
