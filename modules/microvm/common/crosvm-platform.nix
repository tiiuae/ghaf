# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvmFlake,
  ...
}:
let
  inherit (config.networking) hostName;
  cfg = config.microvm;
  crosvmLayoutEnabled = cfg.crosvm.memoryBase != null || cfg.crosvm.platformMmio != null;
  memoryEnd =
    if cfg.crosvm.memoryBase == null then null else cfg.crosvm.memoryBase + cfg.mem * 1024 * 1024;
  platformMmioEnd =
    if cfg.crosvm.platformMmio == null then
      null
    else
      cfg.crosvm.platformMmio.base + cfg.crosvm.platformMmio.size;
  platformDevices = lib.filter ({ bus, ... }: bus == "platform") cfg.devices;
  crosvmRunner = import ./crosvm-runner.nix {
    inherit
      config
      lib
      pkgs
      microvmFlake
      ;
  };
in
{
  _file = ./crosvm-platform.nix;

  options.microvm = {
    devices = lib.mkOption {
      type =
        with lib.types;
        listOf (
          submodule (
            { config, ... }:
            {
              options = {
                bus = lib.mkOption {
                  type = enum [ "platform" ];
                };
                crosvm = {
                  dtSymbol = lib.mkOption {
                    type = nullOr str;
                    default = null;
                    description = "Device-tree symbol that labels this device in a Crosvm overlay.";
                  };
                  guestAddress = lib.mkOption {
                    type = nullOr str;
                    default = null;
                    description = "PCI address assigned to this device in the Crosvm guest.";
                  };
                  mmioBase = lib.mkOption {
                    type = nullOr ints.unsigned;
                    default = null;
                    description = "Exact guest physical address for a single-region Crosvm platform device.";
                  };
                  mapEarly = lib.mkOption {
                    type = bool;
                    default = false;
                    description = "Map this Crosvm platform device before guest execution starts.";
                  };
                  iommu = lib.mkOption {
                    type = enum [
                      "off"
                      "viommu"
                      "coiommu"
                      "pkvm-iommu"
                    ];
                    default = if config.bus == "platform" then "off" else "viommu";
                    defaultText = lib.literalExpression ''if config.bus == "platform" then "off" else "viommu"'';
                    description = "Crosvm IOMMU mode for this device.";
                  };
                };
              };
            }
          )
        );
    };

    crosvm = {
      deviceTreeOverlays = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "Device-tree overlay filenames passed to Crosvm.";
      };
      memoryBase = lib.mkOption {
        type = with lib.types; nullOr ints.unsigned;
        default = null;
        description = "Base guest physical address of Crosvm RAM.";
      };
      platformMmio = lib.mkOption {
        type =
          with lib.types;
          nullOr (submodule {
            options = {
              base = lib.mkOption {
                type = ints.unsigned;
                description = "Base guest physical address of the Crosvm platform MMIO aperture.";
              };
              size = lib.mkOption {
                type = ints.positive;
                description = "Size in bytes of the Crosvm platform MMIO aperture.";
              };
            };
          });
        default = null;
        description = "Explicit Crosvm platform MMIO aperture.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.guest.enable && cfg.hypervisor == "crosvm") {
      microvm.runner.crosvm = lib.mkForce crosvmRunner;
    })
    (lib.mkIf cfg.guest.enable {
      assertions =
        map ({ path, ... }: {
          assertion = cfg.hypervisor == "crosvm";
          message = ''MicroVM ${hostName}: platform device "${path}" is only supported with crosvm.'';
        }) platformDevices
        ++ map ({ path, crosvm, ... }: {
          assertion = crosvm.dtSymbol != null;
          message = ''MicroVM ${hostName}: platform device "${path}" requires `crosvm.dtSymbol`.'';
        }) platformDevices
        ++ [
          {
            assertion = platformDevices == [ ] || cfg.crosvm.deviceTreeOverlays != [ ];
            message = "MicroVM ${hostName}: platform devices require at least one `microvm.crosvm.deviceTreeOverlays` entry.";
          }
          {
            assertion = cfg.crosvm.deviceTreeOverlays == [ ] || cfg.hypervisor == "crosvm";
            message = "MicroVM ${hostName}: `microvm.crosvm.deviceTreeOverlays` is only supported with crosvm.";
          }
        ]
        ++ map (
          {
            path,
            bus,
            crosvm,
            ...
          }:
          {
            assertion = (crosvm.mmioBase == null && !crosvm.mapEarly) || bus == "platform";
            message = ''MicroVM ${hostName}: Crosvm fixed/early mapping for device "${path}" is only supported on the platform bus.'';
          }
        ) cfg.devices
        ++ [
          {
            assertion =
              !crosvmLayoutEnabled || (cfg.hypervisor == "crosvm" && pkgs.stdenv.hostPlatform.isAarch64);
            message = "MicroVM ${hostName}: explicit Crosvm RAM/platform MMIO layout requires AArch64 and the crosvm hypervisor.";
          }
          {
            assertion = (cfg.crosvm.memoryBase == null) == (cfg.crosvm.platformMmio == null);
            message = "MicroVM ${hostName}: `microvm.crosvm.memoryBase` and `microvm.crosvm.platformMmio` must be configured together.";
          }
          {
            assertion =
              memoryEnd == null
              || platformMmioEnd == null
              || memoryEnd <= cfg.crosvm.platformMmio.base
              || platformMmioEnd <= cfg.crosvm.memoryBase;
            message = "MicroVM ${hostName}: Crosvm RAM and platform MMIO ranges overlap.";
          }
        ];
    })
  ];
}
