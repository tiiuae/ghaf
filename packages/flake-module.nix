# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  ...
}:
{
  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
    ./own-pkgs-overlay.nix
  ];
  perSystem = {
    #use the pkgs-by-name-for-flake-parts to get the packages
    # exposed to downstream projects
    pkgsDirectory = ./pkgs-by-name;
  };
}
