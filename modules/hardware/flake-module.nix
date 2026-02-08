# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    hardware-x86_64-workstation.imports = [
      ./definition.nix
      ./x86_64-generic
      ./common
      ./passthrough
      ./common/kernel.nix
    ];
    hardware-x86_64-generic.imports = [
      ./definition.nix
      ./x86_64-generic
      ./passthrough
      ./common/kernel.nix
    ];
    hardware-x86_64-host-kernel.imports = [
      ./x86_64-generic/kernel/host
    ];
    hardware-x86_64-guest-kernel.imports = [
      ./x86_64-generic/kernel/guest
    ];
    hardware-aarch64-generic.imports = [
      ./definition.nix
      ./aarch64/systemd-boot-dtb.nix
      ./passthrough
    ];
  };
}
