# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    microvm.imports = [
      (import ./host/microvm-host.nix { inherit inputs; })
      (import ./sysvms/netvm.nix { inherit inputs; })
      (import ./sysvms/adminvm.nix { inherit inputs; })
      (import ./appvm.nix { inherit inputs; })
      (import ./sysvms/guivm.nix { inherit inputs; })
      (import ./sysvms/audiovm.nix { inherit inputs; })
      (import ./sysvms/idsvm/idsvm.nix { inherit inputs; })
      (import ./sysvms/gpuvm.nix { inherit inputs; })
      ./sysvms/idsvm/mitmproxy
      ./modules.nix
    ];

    mem-manager.imports = [
      ./host/mem-manager.nix
    ];

    vm-modules.imports = [
      ./common/ghaf-audio.nix
      ./common/shared-directory.nix
      ./common/storagevm.nix
      ./common/vm-networking.nix
      ./common/waypipe.nix
      ./common/xdghandlers.nix
      ./common/xdgitems.nix
    ];
  };
}
