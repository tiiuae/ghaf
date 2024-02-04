# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  jetpack-nixos,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.virtualization.guest;
  tegraKernelPackages = jetpack-nixos.legacyPackages.aarch64-linux.kernelPackages;
in {
  options.ghaf.hardware.nvidia.virtualization.guest.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable guest to use Tegra kernel from the host on the Nvidia Orin platform.

      Enable this module directly in the guest vm's configuration.
    '';
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = lib.mkForce tegraKernelPackages;

    boot.kernelPatches = [
      {
        # TODO: This can probably be removed once we move to a newer kernel (from 5.1).
        name = "initdr-modules";
        patch = null;
        extraStructuredConfig = with pkgs.lib; {
          NET_9P = mkDefault kernel.yes;
          NET_9P_VIRTIO = mkDefault kernel.yes;
          NET_9P_DEBUG = mkDefault kernel.yes;
          NET_9P_FS = mkDefault kernel.yes;
          NET_9P_FS_POSIX_ACL = mkDefault kernel.yes;
          PCI = mkDefault kernel.yes;
          # VIRTIO_PCI = mkDefault kernel.yes;
          # PCI_HOST_GENERIC = mkDefault kernel.yes;
        };
      }
    ];

    nixpkgs.overlays = [
      (_final: prev: {
        makeModulesClosure = x:
          prev.makeModulesClosure (x // {allowMissing = true;});
      })
    ];
  };
}
