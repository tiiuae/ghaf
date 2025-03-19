# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{

  flake.nixosModules = {
    hw-laptop.imports = [
      ./definition.nix
      ./x86_64-generic
      ./common/usb/internal.nix
      ./common/usb/external.nix
      ./common/usb/vhotplug.nix
      ./common/devices.nix
      ./common/kernel.nix
      ./common/input.nix
      ./common/qemu.nix
      ./common/shared-mem.nix
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
