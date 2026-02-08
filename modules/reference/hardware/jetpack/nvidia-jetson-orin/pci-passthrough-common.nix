# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.hardware.nvidia.orin;
in
{
  _file = ./pci-passthrough-common.nix;

  options.ghaf.hardware.nvidia.orin.enablePCIPassthroughCommon =
    lib.mkEnableOption "Enable common options related to PCI passthrough on Orin AGX and NX";
  config = lib.mkIf cfg.enablePCIPassthroughCommon {
    boot.kernelModules = [
      "vfio_pci"
      "vfio_iommu_type1"
      "vfio"
    ];
  };
}
