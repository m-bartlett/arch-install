#!/usr/bin/env bash
set -e
rfkill unblock $(rfkill | cut -d' ' -f2 | tail +2 | paste -s -d' ' -)
read -p 'SSID: ' iwctl_ssid
read -p "$iwctl_ssid password: " iwctl_password
iwctl --passphrase "$iwctl_password" station wlan0 connect "$iwctl_ssid"