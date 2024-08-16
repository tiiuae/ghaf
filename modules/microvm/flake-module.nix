# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    microvm.imports = [
      inputs.microvm.nixosModules.host
      ./virtualization/microvm/microvm-host.nix
      (import ./virtualization/microvm/netvm.nix { inherit (inputs) impermanence; })
      ./virtualization/microvm/adminvm.nix
      ./virtualization/microvm/idsvm/idsvm.nix
      ./virtualization/microvm/idsvm/mitmproxy
      (import ./virtualization/microvm/appvm.nix { inherit (inputs) impermanence; })
      (import ./virtualization/microvm/guivm.nix { inherit (inputs) impermanence; })
      ./virtualization/microvm/audiovm.nix
      ./virtualization/microvm/modules.nix
      ./networking.nix
      ./power-control.nix
    ];
  };
}
