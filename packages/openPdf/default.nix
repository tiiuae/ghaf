# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  writeShellApplication,
  dnsutils,
  openssh,
  sshKeyPath,
  ...
}:
# The openpdf script is executed by the xdg handler from the chromium-vm
# It reads the file path, copies it from chromium-vm to zathura-vm and opens it there
writeShellApplication {
  name = "openPdf";
  runtimeInputs = [
    dnsutils
    openssh
  ];
  text = ''
    read -r sourcepath
    filename=$(basename "$sourcepath")
    zathurapath="/var/tmp/$filename"
    chromiumip=$(dig +short chromium-vm | head -1)

    if [[ "$chromiumip" != "$REMOTE_ADDR" ]]; then
      echo "Open PDF request received from $REMOTE_ADDR, but it is only permitted for chromium-vm with IP $chromiumip"
      exit 0
    fi

    echo "Copying $sourcepath from $REMOTE_ADDR to $zathurapath in zathura-vm"
    scp -i ${sshKeyPath} -o StrictHostKeyChecking=no "$REMOTE_ADDR":"$sourcepath" zathura-vm:"$zathurapath"

    echo "Opening $zathurapath in zathura-vm"
    ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no zathura-vm run-waypipe zathura "'$zathurapath'"

    echo "Deleting $zathurapath in zathura-vm"
    ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no zathura-vm rm -f "$zathurapath"

  '';
}
