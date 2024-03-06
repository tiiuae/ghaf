# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
{
  inputs,
  lib,
  self,
  ...
}: let
  inherit (inputs) microvm nixos-generators nixos-hardware;
in
  lib.foldr lib.recursiveUpdate {} [
    {
      imports = [
        ./generic-x86_64/flake-module.nix
        ./lenovo-x1-installer/flake-module.nix
        ./lenovo-x1/flake-module.nix
        ./microchip-icicle-kit/flake-module.nix
        ./nvidia-jetson-orin/flake-module.nix
        ./vm/flake-module.nix
      ];
    }
    (import ./imx8qm-mek.nix {inherit self lib nixos-generators nixos-hardware microvm;})
  ]
