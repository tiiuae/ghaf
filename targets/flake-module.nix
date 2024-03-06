# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
{
  lib,
  inputs,
  self,
  ...
}: let
  inherit (inputs) lanzaboote microvm nixos-generators nixos-hardware nixpkgs disko;
in
  lib.foldr lib.recursiveUpdate {} [
    {
      imports = [
        ./nvidia-jetson-orin/flake-module.nix
      ];
    }
    (import ./vm.nix {inherit self lib nixos-generators microvm;})
    (import ./generic-x86_64.nix {inherit self lib nixos-generators microvm;})
    (import ./lenovo-x1 {inherit self lib microvm lanzaboote disko;})
    (import ./lenovo-x1-carbon-installer.nix {inherit self lib;})
    (import ./imx8qm-mek.nix {inherit self lib nixos-generators nixos-hardware microvm;})
    (import ./microchip-icicle-kit.nix {inherit self lib nixpkgs nixos-hardware;})
  ]
