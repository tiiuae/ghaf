# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    hardware-x86_64-workstation.imports = [
      ./definition.nix
      ./x86_64-generic
      ./common
      ./device-passthrough
    ];
    hardware-x86_64-generic.imports = [
      ./definition.nix
      ./x86_64-generic
      ./device-passthrough
    ];
    hardware-aarch64-generic.imports = [
      ./aarch64/systemd-boot-dtb.nix
    ];
  };
}
