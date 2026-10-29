# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pin nixpkgs in VMs by reference instead of copying its source into each
# VM's store image (~54k files); nix shell and nix-shell fetch it when online.
{ inputs, lib, ... }:
{
  _file = ./vm-nix.nix;

  ghaf.nix.nixpkgs = lib.mkForce null;
  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };
  nix = {
    registry.nixpkgs.to = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      inherit (inputs.nixpkgs) rev;
    };
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
  };

  # Fetching needs a cache dir, which users without a writable home lack
  environment.extraInit = ''
    if [ ! -w "$HOME" ] && [ -n "$XDG_RUNTIME_DIR" ]; then
      export NIX_CACHE_HOME="$XDG_RUNTIME_DIR/nix-cache"
    fi
  '';
}
