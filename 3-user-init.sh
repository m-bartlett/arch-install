#!/usr/bin/env bash

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

cp "$BASH_SOURCE_DIR/etc/xinitrc" "$HOME/.xinitrc"