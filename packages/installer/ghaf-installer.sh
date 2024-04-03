#!/usr/bin/env bash
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# FIXME: Otherwise test fails
if [ -z ${DEVICE_PATH+x} ]; then
    set -euo pipefail
fi

clear
cat <<"EOF"
  ,----..     ,---,
 /   /   \  ,--.' |                 .--.,
|   :     : |  |  :               ,--.'  \
.   |  ;. / :  :  :               |  | /\/
.   ; /--`  :  |  |,--.  ,--.--.  :  : :
;   | ;  __ |  :  '   | /       \ :  | |-,
|   : |.' .'|  |   /' :.--.  .-. ||  : :/|
.   | '_.' :'  :  | | | \__\/: . .|  |  .'
'   ; : \  ||  |  ' | : ," .--.; |'  : '
'   | '/  .'|  :  :_:,'/  /  ,.  ||  | |
|   :    /  |  | ,'   ;  :   .'   \  : \
 \   \ .'   `--''     |  ,     .-./  |,'
  `---`                `--`---'   `--'
EOF

echo "Welcome to Ghaf installer!"

if [ -z ${DEVICE_PATH+x} ]; then
    echo "To install image choose path to the device on which image will be installed."

    lsblk
    read -r -p "Device path [e.g. /dev/nvme0n1]: " DEVICE_PATH

    read -r -p 'WARNING: Next command will destroy all previous data from your device, press Enter to proceed. '
fi

echo "Installing..."
disko-install --write-efi-boot-entries --debug --flake "$GHAF_SOURCE#$TARGET_NAME" --disk "$DISKO_DISK_NAME" "$DEVICE_PATH" --option substitute false --option binary-caches ""

echo ""
echo "Installation done. Please remove the installation media and reboot"
