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
read -p "Device name [e.g. sda]: " DEVICE_NAME

export DISKO_CONFIG_FILE_WITH_DRIVE="$HOME/disk-config.nix"

sed "s/DRIVE_PATH/\/dev\/$DEVICE_NAME/g" '@diskoConfig@' > $DISKO_CONFIG_FILE_WITH_DRIVE
cat $DISKO_CONFIG_FILE_WITH_DRIVE
echo $DISKO_CONFIG_FILE_WITH_DRIVE

read -p 'WARNING: Next commmand will destory all previous data from your device, press Enter to proceed. '
echo "Partitioning..."
disko --no-deps --debug --mode disko $DISKO_CONFIG_FILE_WITH_DRIVE

read -p "Press Enter to install system"

echo "Installing..."
nixos-install --option binary-caches “” --no-root-passwd --system "@toplevelDrv@"

read -p "Press Enter to reboot"

echo "Rebooting..."
sleep 1
reboot
