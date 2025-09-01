# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    development.imports = [
      inputs.srvos.nixosModules.mixins-nix-experimental
      ./cuda.nix
      ./debug-tools.nix
      ./dt-gui.nix
      ./nix.nix
      ./ssh.nix
      ./usb-serial.nix
      # TODO this looks like the raw nixpkgs, we should probably
      # use the one that has been customized with overlays etc
      { ghaf.development.nix-setup.nixpkgs = inputs.nixpkgs; }
    ];
  };
}
