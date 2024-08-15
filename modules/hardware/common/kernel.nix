# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Kernel Configuration Definitions
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types optionalAttrs;
  inherit (builtins) concatStringsSep filter map hasAttr;

  # Only x86 targets with hw definition supported at the moment
  inherit (pkgs.stdenv.hostPlatform) isx86;
  fullVirtualization = isx86 && (hasAttr "hardware" config.ghaf);
in {
  options.ghaf.kernel = {
    host = mkOption {
      type = types.attrs;
      default = {};
      description = "Host kernel configuration";
    };
    guivm = mkOption {
      type = types.attrs;
      default = {};
      description = "GuiVM kernel configuration";
    };
    audiovm = mkOption {
      type = types.attrs;
      default = {};
      description = "AudioVM kernel configuration";
    };
  };

  config = {
    # Host kernel configuration
    boot = optionalAttrs fullVirtualization {
      initrd = {
        inherit (config.ghaf.hardware.definition.host.kernelConfig.stage1) kernelModules;
      };
      inherit (config.ghaf.hardware.definition.host.kernelConfig.stage2) kernelModules;
      kernelParams = let
        # PCI device passthroughs for vfio
        filterDevices = filter (d: d.vendorId != null && d.productId != null);
        mapPciIdsToString = map (d: "${d.vendorId}:${d.productId}");
        vfioPciIds = mapPciIdsToString (filterDevices (
          config.ghaf.hardware.definition.network.pciDevices
          ++ config.ghaf.hardware.definition.gpu.pciDevices
          ++ config.ghaf.hardware.definition.audio.pciDevices
        ));
        hugePagesArg =
          if config.ghaf.profiles.applications.ivShMemServer.enable
          then let
            hugepagesz = "2M"; # valid values: "2M" and "1G", as kernel supports these huge pages' size
            hugepages =
              if hugepagesz == "2M"
              then config.ghaf.profiles.applications.ivShMemServer.memSize / 2
              else config.ghaf.profiles.applications.ivShMemServer.memSize / 1024;
          in [
            "hugepagesz=${hugepagesz}"
            "hugepages=${toString hugepages}"
          ]
          else [];
      in
        config.ghaf.hardware.definition.host.kernelConfig.kernelParams
        ++ [
          "vfio-pci.ids=${concatStringsSep "," vfioPciIds}"
        ]
        ++ hugePagesArg;
    };

    # Guest kernel configurations
    ghaf.kernel = optionalAttrs fullVirtualization {
      guivm = {
        boot = {
          initrd = {
            inherit (config.ghaf.hardware.definition.gpu.kernelConfig.stage1) kernelModules;
          };
          inherit (config.ghaf.hardware.definition.gpu.kernelConfig.stage2) kernelModules;
          kernelParams = let
            flatMemArg =
              if config.ghaf.profiles.applications.ivShMemServer.enable
              then [
                "kvm_ivshmem.flataddr=${config.ghaf.profiles.applications.ivShMemServer.flataddr}"
              ]
              else [];
          in
            config.ghaf.hardware.definition.gpu.kernelConfig.kernelParams ++ flatMemArg;
        };
      };
      audiovm = {
        boot = {
          initrd = {
            inherit (config.ghaf.hardware.definition.audio.kernelConfig.stage1) kernelModules;
          };
          inherit (config.ghaf.hardware.definition.audio.kernelConfig.stage2) kernelModules;
          inherit (config.ghaf.hardware.definition.audio.kernelConfig) kernelParams;
        };
      };
    };
  };
}
