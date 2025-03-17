# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{

  flake.nixosModules = {
    laptop.imports = [
      ./definition.nix
      ./x86_64-generic
      ./laptop.nix
      ./common
    ];
    hw-x86_64-generic.imports = [
      ./definition.nix
      ./x86_64-generic
    ];
    aarch64-generic.imports = [
      ./aarch64/systemd-boot-dtb.nix
    ];
  };
}
