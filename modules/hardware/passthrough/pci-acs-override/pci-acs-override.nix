# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.passthrough.pciAcsOverride;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;

  # Convert device IDs to kernel parameter format (id:VENDOR:DEVICE)
  idOptions = map (id: "id:${id}") cfg.ids;
in
{
  _file = ./pci-acs-override.nix;

  options.ghaf.hardware.passthrough.pciAcsOverride = {
    enable = mkEnableOption "PCIe ACS (Access Control Services) override support for VFIO device assignment";

    ids = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "8086:550a"
        "8086:7702"
      ];
      description = ''
        List of specific PCI device IDs (vendor:device in hex) to override ACS.
        This works for ALL PCI devices including non-PCIe devices.

        Use this when you need to split IOMMU groups for specific devices
        that are not PCIe (e.g., LPC/eSPI devices like Intel 00:1f.x).
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ids != [ ];
        message = "pciAcsOverride: 'ids' cannot be empty when enabled.";
      }
    ];

    boot.kernelPatches = [
      {
        name = "pci-acs-override";
        patch = ./0001-pci-add-pcie_acs_override-for-pci-passthrough.patch;
      }
    ];

    boot.kernelParams = [
      "pcie_acs_override=${lib.concatStringsSep "," idOptions}"
    ];

    warnings = [
      ''
        PCIe ACS Override is enabled. This overrides hardware isolation boundaries
        and IOMMU group assignments. Only use this if you understand the security
        implications for your specific hardware topology and use case.

        Device IDs: ${lib.concatStringsSep ", " cfg.ids}
      ''
    ];
  };
}
