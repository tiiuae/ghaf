{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin;
in {
  options.ghaf.hardware.nvidia.orin.enablePCIPassthroughCommon =
    lib.mkEnableOption
    "Enable common options related to PCI passthrough on Orin AGX and NX";
  config = lib.mkIf cfg.enablePCIPassthroughCommon {
    boot.kernelModules = [
      "vfio_pci"
      "vfio_iommu_type1"
      "vfio"
    ];
  };
}
