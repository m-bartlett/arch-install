#!/usr/bin/env bash

user=$(whoami)

chmod go-w /home/$user
chmod 700 /home/$user/.ssh
chmod 600 /home/$user/.ssh/authorized_keys
chmod 400 /home/$user/.ssh/*id_rsa

# git clone https://aur.archlinux.org/yay.git
git clone https://aur.archlinux.org/yay-bin.git
pushd yay-bin
makepkg -Arcis --noconfirm
popd
rm -rf yay-bin

aur_packages=(
  nerd-fonts-victor-mono
  vim-clipboard
  web-media-controller-mpris-git
  libxft-bgra
)

yay -Sya --noconfirm ${aur_packages[@]}


xdg-user-dirs-update
mkdir -p $HOME/.ssh
mkdir -p $HOME/Images
mkdir -p $HOME/Projects
rmdir $HOME/Documents  &> /dev/null
rmdir $HOME/Pictures   &> /dev/null
rmdir $HOME/Templates  &> /dev/null
rmdir $HOME/Public     &> /dev/null
xdg-user-dirs-update

sudo pip3 install pyaes
sudo pip3 install pytuya

cp /xprofile "$HOME/.xprofile"