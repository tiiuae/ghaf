# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    microvm.imports = [
      inputs.microvm.nixosModules.host
      ./virtualization/microvm/microvm-host.nix
      ./virtualization/microvm/netvm.nix
      ./virtualization/microvm/adminvm.nix
      ./virtualization/microvm/idsvm/idsvm.nix
      ./virtualization/microvm/idsvm/mitmproxy
      ./virtualization/microvm/appvm.nix
      ./virtualization/microvm/guivm.nix
      ./virtualization/microvm/audiovm.nix
      ./virtualization/microvm/modules.nix
      ./networking.nix
      ./power-control.nix
    ];
  };
}
