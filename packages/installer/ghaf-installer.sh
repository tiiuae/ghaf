#! @runtimeShell@
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
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

echo "To install image choose path to the device on which image will be installed."

lsblk
read -p "Device name [e.g. /dev/nvme0n1]: " DEVICE_NAME

read -p 'WARNING: Next command will destroy all previous data from your device, press Enter to proceed. '

echo "Installing..."
dd if=@imagePath@ of="${DEVICE_NAME}" bs=32M status=progress

echo ""
echo "Installation done. Please remove the installation media and reboot"
