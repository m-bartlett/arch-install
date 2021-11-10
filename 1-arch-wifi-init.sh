#!/usr/bin/env bash
set -e
if [ -n "$1" ] && [ -f "$1" ]; then
  iwctl_ssid="${1%*.wifi}"
  iwctl_password="$(<"$1")"
else
  read -p 'SSID: ' iwctl_ssid
  read -p "$iwctl_ssid password: " iwctl_password
fi
rfkill unblock $(rfkill | cut -d' ' -f2 | tail +2 | paste -s -d' ' -)
sleep 3 # Allow time for the network name to become "valid"
iwctl --passphrase "$iwctl_password" station wlan0 connect "$iwctl_ssid"