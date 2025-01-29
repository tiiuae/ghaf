# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    microvm.imports = [
      inputs.microvm.nixosModules.host
      (import ./virtualization/microvm/microvm-host.nix { inherit inputs; })
      (import ./virtualization/microvm/netvm.nix { inherit inputs; })
      (import ./virtualization/microvm/adminvm.nix { inherit inputs; })
      (import ./virtualization/microvm/appvm.nix { inherit inputs; })
      (import ./virtualization/microvm/guivm.nix { inherit inputs; })
      (import ./virtualization/microvm/audiovm.nix { inherit inputs; })
      (import ./virtualization/microvm/idsvm/idsvm.nix { inherit inputs; })
      ./virtualization/microvm/idsvm/mitmproxy
      ./virtualization/microvm/modules.nix
      ./networking.nix
      ./power-control.nix
      ../hardware/common/shared-mem.nix
    ];
  };
}
