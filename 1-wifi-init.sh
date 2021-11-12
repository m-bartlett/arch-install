#!/usr/bin/env bash
set -e

wifi_files="$(\ls -1 *.wifi)"

if [ -n "$wifi_files" ]; then
  select wifi_file in $wifi_files; do : ; break; done
  iwctl_ssid="${wifi_file%*.wifi}"
  iwctl_password="$(<"$wifi_file")"
else
  read -p 'SSID: ' iwctl_ssid
  read -p "$iwctl_ssid password: " iwctl_password
fi

rfkill unblock $(rfkill | cut -d' ' -f2 | tail +2 | paste -s -d' ' -)
sleep 3 # Allow time for the network name to become "valid"
iwctl --passphrase "$iwctl_password" station wlan0 connect "$iwctl_ssid"

export iwctl_ssid iwctl_password