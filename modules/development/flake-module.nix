# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    development.imports = [
      ./cuda.nix
      ./debug-tools.nix
      ./dt-gui.nix
      ./nix.nix
      ./ssh.nix
      ./usb-serial.nix
      { ghaf.development.nix-setup.nixpkgs = inputs.nixpkgs; }
    ];
  };
}
