# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  _file = ./flake-module.nix;

  flake.nixosModules = {
    development.imports = [
      inputs.srvos.nixosModules.mixins-nix-experimental
      ./cuda.nix
      ./debug-tools.nix
      ./dt-av.nix
      ./dt-gui.nix
      ./dt-host.nix
      ./dt-net.nix
      ./nix.nix
      ./usb-serial.nix
      # Pin `nixpkgs` for nixPath/registry on debug builds only.
      #
      # The value is the nixpkgs *source* -- 480 MB unpacked, a 203 MB closure.
      #
      # `nix-setup.enable` stays untouched: release still wants the daemon
      # settings (experimental-features, keep-outputs, automatic gc). Only the
      # source pin is dropped -- with `nixpkgs = null`, nix.nix leaves both
      # `nixPath` and `registry` undefined.
      #
      # TODO this looks like the raw nixpkgs, we should probably
      # use the one that has been customized with overlays etc
      (
        { config, lib, ... }:
        {
          ghaf.development.nix-setup.nixpkgs = lib.mkIf config.ghaf.profiles.debug.enable inputs.nixpkgs;
        }
      )
    ];
  };
}
