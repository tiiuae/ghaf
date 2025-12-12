# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    development.imports = [
      inputs.srvos.nixosModules.mixins-nix-experimental
      ./cuda.nix
      ./debug-tools.nix
      ./dt-av.nix
      ./dt-gui.nix
      ./dt-host.nix
      ./dt-net.nix
      ./ssh.nix
      ./usb-serial.nix
    ];
  };
}
