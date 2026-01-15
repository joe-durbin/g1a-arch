#!/bin/bash

# 1. Get list of available configs (removing the .conf extension)
CONFIGS=$(ls ~/.config/vpn/*.conf | xargs -n 1 basename | sed 's/\.conf//g')

# 2. Identify currently active VPN service
ACTIVE_VPN=$(systemctl list-units --type=service --state=running | grep -oP 'openvpn-client@\K[^.]+')

# 3. Create the menu list
if [ -n "$ACTIVE_VPN" ]; then
  MENU="STOP: $ACTIVE_VPN\n$CONFIGS"
else
  MENU="$CONFIGS"
fi

# 4. Show the menu using fuzzel (better for Wayland) or rofi
CHOICE=$(echo -e "$MENU" | fuzzel --dmenu -p "Select VPN: ")

# 5. Execute the choice
if [[ "$CHOICE" == STOP:* ]]; then
  sudo systemctl stop "openvpn-client@$ACTIVE_VPN"
elif [ -n "$CHOICE" ]; then
  # Stop any existing VPN first to avoid conflicts
  if [ -n "$ACTIVE_VPN" ]; then
    sudo systemctl stop "openvpn-client@$ACTIVE_VPN"
  fi
  sudo systemctl start "openvpn-client@$CHOICE"
fi
