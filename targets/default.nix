# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
{
  lib,
  inputs,
  ...
}: let
  inherit (inputs) jetpack-nixos lanzaboote microvm nixos-generators nixos-hardware nixpkgs disko self;
in
  lib.foldr lib.recursiveUpdate {} [
    (import ./nvidia-jetson-orin {inherit lib nixpkgs nixos-generators microvm jetpack-nixos;})
    (import ./vm.nix {inherit lib nixos-generators microvm;})
    (import ./generic-x86_64.nix {inherit lib nixos-generators microvm;})
    (import ./lenovo-x1-carbon.nix {inherit lib microvm lanzaboote disko;})
    (import ./lenovo-x1-carbon-installer.nix {inherit self lib;})
    (import ./imx8qm-mek.nix {inherit lib nixos-generators nixos-hardware microvm;})
    (import ./microchip-icicle-kit.nix {inherit lib nixpkgs nixos-hardware;})
  ]
