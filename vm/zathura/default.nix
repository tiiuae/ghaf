# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2022 Alyssa Ross <hi@alyssa.is><
# SPDX-FileCopyrightText: 2022 Unikie

{ config }:

import ../../../spectrum/vm/make-vm.nix { inherit config; } {
    wayland = true;
    run = config.pkgs.callPackage (
      { writeScript, zathura, wayland-proxy-virtwl }:
      writeScript "appvm-zathura-run" ''
        #!/bin/execlineb -P
        if { modprobe virtio-gpu }
        foreground { ln -ns /run/ext /run/opengl-driver }
        foreground { mkdir /run/user }
        foreground {
          umask 077
          mkdir /run/user/0
        }
        export XDG_RUNTIME_DIR /run/user/0
        ${wayland-proxy-virtwl}/bin/wayland-proxy-virtwl --virtio-gpu
        "${zathura}/bin/zathura"
      ''
    ) {};
}
