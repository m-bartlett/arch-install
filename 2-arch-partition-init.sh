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
LUKS name = $cryptfsname

EOF

read -p "Continue? [y/N]: " input ; echo
if [ "${input,,}" != "y" ]; then
  echo "Quitting..."
  exit 1
fi

export hostname user password device cryptfsname


set -x

#### Partitioning

## A separate, unencrypted boot partition is needed for disk encryption
## Make efi, boot, swap, and root
## 1 200MB Boot partition # Hex code ef02
## 2 100MB EFI partition # Hex code ef00
## 3 <RAM size> swap partition
## 4 100% size partiton # (to be encrypted) Hex code 8300

ram_size=$(free --mega | awk '/Mem:/ {print $2}')

sgdisk --zap-all "${device}"
sgdisk --clear --mbrtogpt "${device}"
sgdisk --set-alignment=2048 "${device}"

# ef00 is essential for GPT booting in UEFI
sgdisk --new 1:2048:+200M      --typecode 1:ef02 --change-name 1:boot "${device}"  # ef02 BIOS boot
sgdisk --new 2:0:+100M         --typecode 2:ef00 --change-name 2:EFI  "${device}"  # ef00 (Extensible Firmware Interface (EFI)) System Partition (ESP)
sgdisk --new 3:0:+${ram_size}M --typecode 3:8200 --change-name 3:swap "${device}"  # 8200 Linux swap
sgdisk --new 4:0:0             --typecode 4:8300 --change-name 4:root "${device}"  # 8300 Linux filesystem



### Setup the disk and partitions ###

export part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
export  part_efi="$(ls ${device}* | grep -E "^${device}p?2$")"
export part_swap="$(ls ${device}* | grep -E "^${device}p?3$")"
export part_root="$(ls ${device}* | grep -E "^${device}p?4$")"

wipefs "${part_efi}"
wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 -n "EFI" "${part_efi}"
mkfs.ext4 -L boot "${part_boot}"



#### Encrypted root

modprobe dm-crypt
modprobe dm-mod
cryptsetup -y -v luksFormat -s 512 -h sha512 "${part_root}" <<<"$cryptpassphrase"$'\n'"$cryptpassphrase"
cryptsetup open "${part_root}" ${cryptfsname} <<<"$cryptpassphrase"
mkfs.ext4 -L root /dev/mapper/${cryptfsname}



#### Init boot and swap

## Start swap
mkswap "${part_swap}"
swapon "${part_swap}"

## Mount root
mount /dev/mapper/${cryptfsname} /mnt

# Mount boot
mkdir /mnt/boot
mount "$part_boot" /mnt/boot

# Mount efi
mkdir /mnt/boot/efi
mount "$part_efi" /mnt/boot/efi


pacstrap /mnt \
               base            \
               base-devel      \
               efibootmgr      \
               linux           \
               linux-firmware  \
               vi              \
               dhcpcd          \
               wpa_supplicant  \
               grub-efi-x86_64 \
               git             \
               openssh         \
               wifi-menu       \
               dhcpcd          \
               netctl          \
               man-db          \
               man-pages       \
               texinfo         \


mkdir -p /mnt/etc
genfstab -pU /mnt >> /mnt/etc/fstab
echo 'tmpfs'$'\t''/tmp'$'\t''tmpfs'$'\t''defaults,noatime,mode=1777'$'\t''0'$'\t''0' >> /mnt/etc/fstab

cp -v $BASH_SOURCE_DIR/3-*.sh /mnt/arch-init.sh
arch-chroot /mnt /arch-init.sh
rm /mnt/arch-init.sh

clear
echo "Done!"
echo

read -p "Unmount now? [y/N]: " -n 1 input ; echo
if [ "${input,,}" == "y" ]; then
  umount -R /mnt
  swapoff -a
  cryptsetup close /dev/mapper/${cryptfsname}
  echo "Unmounted."
fi

echo

read -p "Reboot? [y/N]: " -n 1 input ; echo
[ "${input,,}" == "y" ] && reboot