# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  ...
}:
let
  waypipePort = 1100; # TODO: remove hardcoded port number
  idsvmIP = "ids-vm";
  displayOpt =
    if configHost.ghaf.shm.service.gui.enabled then
      "-s ${configHost.ghaf.shm.service.gui.clientSocketPath}"
    else
      "--vsock -s ${toString waypipePort}";
  mitmwebUI = pkgs.writeShellScript "mitmweb-ui" ''
    # Create ssh-tunnel between chrome-vm and ids-vm
    ${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -t ghaf@chrome-vm \
            ${pkgs.openssh}/bin/ssh -M -S /tmp/control_socket \
            -f -N -L 8081:localhost:8081 ghaf@${idsvmIP}
    # TODO: check pipe creation failures

    # Launch google-chrome application and open mitmweb page
    ${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no chrome-vm \
        ${pkgs.waypipe}/bin/waypipe --border=#ff5733,5 ${displayOpt}} server \
        google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland \
        http://localhost:8081

    # Use the control socket to close the ssh tunnel between chrome-vm and ids-vm
    ${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 \
        -o StrictHostKeyChecking=no \
        -t ghaf@chrome-vm \
            ${pkgs.openssh}/bin/ssh -q -S /tmp/control_socket -O exit ghaf@${idsvmIP}
  '';
in
stdenvNoCC.mkDerivation {
  name = "mitmweb-ui";

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${mitmwebUI} $out/bin/mitmweb-ui
  '';

  meta = with lib; {
    description = "Script to launch Google Chrome to open mitmweb interface using ssh-tunneling and authentication.";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
