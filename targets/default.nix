# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
{
  self,
  lib,
  inputs,
  config,
  ...
}: let
  inherit (inputs) jetpack-nixos microvm nixos-generators nixos-hardware nixpkgs;
in
  lib.foldr lib.recursiveUpdate {} [
    #(import ./nvidia-jetson-orin {inherit lib nixpkgs nixos-generators microvm jetpack-nixos;})
    #(import ./vm.nix {inherit lib nixos-generators microvm;})
    #(import ./generic-x86_64.nix {inherit lib nixos-generators microvm;})
    #(import ./lenovo-x1-carbon.nix {inherit self lib config inputs;})
    #(import ./imx8qm-mek.nix {inherit lib nixos-generators nixos-hardware microvm;})
    #(import ./microchip-icicle-kit.nix {inherit self lib nixpkgs nixos-hardware;})
  ]
