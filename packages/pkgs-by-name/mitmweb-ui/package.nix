# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  openssh,
  waypipe,
}:
let
  waypipePort = 1100; # TODO: remove hardcoded port number
  idsvmIP = "ids-vm";
in
writeShellApplication {
  name = "mitmweb-ui";

  runtimeInputs = [
    openssh
    waypipe
  ];

  text = ''
    # Create ssh-tunnel between chrome-vm and ids-vm
    ${openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -t ghaf@chrome-vm \
            ${openssh}/bin/ssh -M -S /tmp/control_socket \
            -f -N -L 8081:localhost:8081 ghaf@${idsvmIP}
    # TODO: check pipe creation failures

    # Launch google-chrome application and open mitmweb page
    ${openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no chrome-vm \
        ${waypipe}/bin/waypipe --border=#ff5733,5 --vsock -s ${toString waypipePort} server \
        google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland \
        http://localhost:8081

    # Use the control socket to close the ssh tunnel between chrome-vm and ids-vm
    ${openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -t ghaf@chrome-vm \
            ${openssh}/bin/ssh -q -S /tmp/control_socket -O exit ghaf@${idsvmIP}
  '';
  meta = {
    description = "UI for mitmweb";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
