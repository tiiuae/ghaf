# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# List of target configurations
{
  self,
  nixpkgs,
  nixos-generators,
  nixos-hardware,
  microvm,
  jetpack-nixos,
}:
nixpkgs.lib.foldr nixpkgs.lib.recursiveUpdate {} [
  (import ./nvidia-jetson-orin.nix {inherit self nixpkgs nixos-generators microvm jetpack-nixos;})
  (import ./vm.nix {inherit self nixpkgs nixos-generators microvm;})
  (import ./intel-nuc.nix {inherit self nixpkgs nixos-generators microvm;})
  (import ./imx8qm-mek.nix {inherit self nixpkgs nixos-generators nixos-hardware microvm;})
]
