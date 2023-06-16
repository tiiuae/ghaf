# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Top-level module entry point for the Orin family of chips
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  imports = [
    ./partition-template.nix
    ../../boot/systemd-boot-dtb.nix
    {
      ghaf.boot.loader.systemd-boot-dtb.enable = true;
    }

    ./jetson-orin.nix
    {
      ghaf.hardware.nvidia.orin.enable = true;
    }
  ];
}
