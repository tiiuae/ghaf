# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    microvm.imports = [
      inputs.microvm.nixosModules.host
      (import ./microvm-host.nix { inherit inputs; })
      (import ./sysvms/netvm.nix { inherit inputs; })
      (import ./sysvms/adminvm.nix { inherit inputs; })
      (import ./appvm.nix { inherit inputs; })
      (import ./sysvms/guivm.nix { inherit inputs; })
      (import ./sysvms/audiovm.nix { inherit inputs; })
      (import ./sysvms/idsvm/idsvm.nix { inherit inputs; })
      ./sysvms/idsvm/mitmproxy
      ./modules.nix
      ./networking.nix
      ./power-control.nix
      ../hardware/common/shared-mem.nix
    ];

    mem-manager.imports = [
      {
        nixpkgs.overlays = [
          inputs.ghafpkgs.overlays.default
          (_final: prev: {
            mem-manager = inputs.ghafpkgs.packages.${prev.stdenv.hostPlatform.system}.ghaf-mem-manager;
          })
        ];
      }
      ./mem-manager.nix
    ];
  };
}
