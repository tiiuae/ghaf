# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  writeShellApplication,
  dnsutils,
  openssh,
  sshKeyPath,
  user,
  ...
}:
# This script is executed in the GUIVM by the Ghaf XDG systemd service when it receives an XDG open request.
# It reads the file path and type, copies the file to the zathura-vm, and opens it with the corresponding application.
writeShellApplication {
  name = "ghaf-xdg-open";
  runtimeInputs = [
    dnsutils
    openssh
  ];
  text = ''
    read -r type
    read -r sourcepath
    filename=$(basename "$sourcepath")
    zathurapath="/var/tmp/$filename"

    googlechromevmip=$(dig +short chrome-vm | head -1)
    businessvmip=$(dig +short business-vm | head -1)
    commsvmip=$(dig +short comms-vm | head -1)

    if [[ "127.0.0.1" != "$REMOTE_ADDR" && \
      "$businessvmip" != "$REMOTE_ADDR" && \
      "$googlechromevmip" != "$REMOTE_ADDR" && \
      "$commsvmip" != "$REMOTE_ADDR" ]]; then
      echo "Open PDF request received from $REMOTE_ADDR, but it is only permitted for chrome-vm, business-vm, comms-vm, or gui-vm"
      exit 0
    fi

    if [[ "127.0.0.1" != "$REMOTE_ADDR" ]]; then
      echo "Copying $sourcepath from $REMOTE_ADDR to $zathurapath in zathura-vm"
      scp -i ${sshKeyPath} -o StrictHostKeyChecking=no ${user}@"$REMOTE_ADDR":"$sourcepath" ${user}@zathura-vm:"$zathurapath"
    else
      echo "Copying $sourcepath from GUIVM to $zathurapath in zathura-vm"
      scp -i ${sshKeyPath} -o StrictHostKeyChecking=no "$sourcepath" ${user}@zathura-vm:"$zathurapath"
    fi

    echo "Opening $zathurapath in zathura-vm"
    if [[ "$type" == "pdf" ]]; then
      ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no ${user}@zathura-vm run-waypipe zathura "'$zathurapath'"
    elif [[ "$type" == "image" ]]; then
      ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no ${user}@zathura-vm run-waypipe pqiv -i "'$zathurapath'"
    else
      echo "Unknown type: $type"
    fi

    echo "Deleting $zathurapath in zathura-vm"
    ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no ${user}@zathura-vm rm -f "$zathurapath"

  '';
}
