# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvmFlake,
  ...
}:
let
  cfg = config.microvm;
  extensionNeeded = cfg.crosvm.memoryBase != null || cfg.crosvm.pciDeviceOptions != { };
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

  options.microvm.crosvm = {
    memoryBase = lib.mkOption {
      type = with lib.types; nullOr ints.unsigned;
      default = null;
      description = "Base guest physical address of Crosvm RAM.";
    };

    pciDeviceOptions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            guestAddress = lib.mkOption {
              type = with lib.types; nullOr str;
              default = null;
              description = "PCI address assigned to this device in the Crosvm guest.";
            };
            iommu = lib.mkOption {
              type = lib.types.enum [
                "off"
                "viommu"
                "coiommu"
                "pkvm-iommu"
              ];
              default = "viommu";
              description = "Crosvm IOMMU mode for this PCI device.";
            };
            dtSymbol = lib.mkOption {
              type = with lib.types; nullOr str;
              default = null;
              description = "Optional device-tree symbol for this PCI device.";
            };
          };
        }
      );
      default = { };
      description = "Crosvm-specific options for PCI entries already present in microvm.devices.";
    };
  };

  config = lib.mkIf cfg.guest.enable {
    assertions = [
      {
        assertion =
          cfg.crosvm.memoryBase == null || (cfg.hypervisor == "crosvm" && pkgs.stdenv.hostPlatform.isAarch64);
        message = "MicroVM ${config.networking.hostName}: an explicit Crosvm RAM base requires AArch64 and the crosvm hypervisor.";
      }
      {
        assertion = lib.all (
          path: lib.any (device: device.bus == "pci" && device.path == path) cfg.devices
        ) (lib.attrNames cfg.crosvm.pciDeviceOptions);
        message = "MicroVM ${config.networking.hostName}: every Crosvm PCI option must name a PCI entry in microvm.devices.";
      }
    ];

    microvm.runner.crosvm = lib.mkIf (cfg.hypervisor == "crosvm" && extensionNeeded) (
      lib.mkForce crosvmRunner
    );
  };
}
