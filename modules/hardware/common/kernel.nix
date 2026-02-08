# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Kernel Configuration Definitions
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types optionalAttrs;

  # Only x86 targets with hw definition supported at the moment
  # TODO: this should at the very least be isx86_64
  inherit (pkgs.stdenv.hostPlatform) isx86;
  fullVirtualization = isx86 && (builtins.hasAttr "hardware" config.ghaf);
in
{
  options.ghaf.kernel = {
    host = mkOption {
      type = types.attrs;
      default = { };
      description = "Host kernel configuration";
    };
    guivm = mkOption {
      type = types.attrs;
      default = { };
      description = "GuiVM kernel configuration";
    };
    audiovm = mkOption {
      type = types.attrs;
      default = { };
      description = "AudioVM kernel configuration";
    };
    netvm = mkOption {
      type = types.attrs;
      default = { };
      description = "NetVM kernel configuration";
    };
  };

  options.ghaf.host.kernel.memory-wipe = {
    enable = lib.mkEnableOption "Memory wipe on boot and free using kernel configuration (host only)";
  };

  config = lib.mkMerge [
    # Memory wipe kernel patches (applies to host only)
    {
      boot.kernelPatches = lib.optionals config.ghaf.host.kernel.memory-wipe.enable [
        {
          name = "memory-wipe-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            # Enable page poisoning for additional security
            PAGE_POISONING = yes;

            # Enable init-on-alloc and init-on-free support
            INIT_ON_ALLOC_DEFAULT_ON = option yes;
            INIT_ON_FREE_DEFAULT_ON = option yes;
          };
        }
      ];
    }

    # Host kernel configuration (only for full virtualization)
    {
      boot = optionalAttrs fullVirtualization {
        initrd = {
          inherit (config.ghaf.hardware.definition.host.kernelConfig.stage1) kernelModules;
        };
        kernelModules =
          let
            # PCI device passthroughs for vfio
            filterDevices = builtins.filter (d: d.vendorId != null && d.productId != null);
            pciDevices = filterDevices (
              config.ghaf.hardware.definition.network.pciDevices
              ++ config.ghaf.hardware.definition.gpu.pciDevices
              ++ config.ghaf.hardware.definition.audio.pciDevices
            );
            hasPciPassthrough =
              pciDevices != [ ] || config.ghaf.hardware.definition.host.extraVfioPciIds != [ ];
          in
          config.ghaf.hardware.definition.host.kernelConfig.stage2.kernelModules
          # The vfio-pci module must be loaded for PCI passthrough to work
          ++ lib.optionals hasPciPassthrough [ "vfio_pci" ];
        kernelParams =
          let
            # PCI device passthroughs for vfio
            filterDevices = builtins.filter (d: d.vendorId != null && d.productId != null);
            mapPciIdsToString = map (d: "${d.vendorId}:${d.productId}");
            vfioPciIds =
              mapPciIdsToString (
                filterDevices (
                  config.ghaf.hardware.definition.network.pciDevices
                  ++ config.ghaf.hardware.definition.gpu.pciDevices
                  ++ config.ghaf.hardware.definition.audio.pciDevices
                )
              )
              ++ config.ghaf.hardware.definition.host.extraVfioPciIds;
          in
          config.ghaf.hardware.definition.host.kernelConfig.kernelParams
          ++ [ "vfio-pci.ids=${builtins.concatStringsSep "," vfioPciIds}" ];
      };
    }

    # Guest kernel configurations
    {
      ghaf.kernel = optionalAttrs fullVirtualization {
        guivm = {
          boot = {
            initrd = {
              inherit (config.ghaf.hardware.definition.gpu.kernelConfig.stage1) kernelModules;
            };
            inherit (config.ghaf.hardware.definition.gpu.kernelConfig.stage2) kernelModules;
            inherit (config.ghaf.hardware.definition.gpu.kernelConfig) kernelParams;
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
        netvm = {
          boot = {
            initrd = {
              inherit (config.ghaf.hardware.definition.network.kernelConfig.stage1) kernelModules;
            };
            inherit (config.ghaf.hardware.definition.network.kernelConfig.stage2) kernelModules;
            inherit (config.ghaf.hardware.definition.network.kernelConfig) kernelParams;
          };
        };
      };
    }
  ];
}
