# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.virtualization;
  providerHostEnabled = config.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers != { };
  kernelVersion = config.boot.kernelPackages.kernel.version;
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport.override {
    inherit (cfg) bpmpAllowAllDomains;
  };
  sourcesPatch = pkgs.runCommand "bpmp-virt-sources.patch" { } ''
    cp ${support}/patches/linux/bpmp-sources.patch "$out"
  '';
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.virtualization = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable virtualization support for NVIDIA Orin.

        This compatibility option is toggled automatically by the existing
        Ghaf passthrough modules while their guest policy moves to
        jetpack-nixos.
      '';
    };

    sourcesPatch = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = sourcesPatch;
      defaultText = lib.literalExpression "<jetpack-nixos BPMP sources patch>";
      description = "BPMP proxy sources supplied by jetpack-nixos.";
    };

    bpmpAllowAllDomains = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow every BPMP clock, reset and power-domain request.

        This is dangerous and intended only for temporary policy discovery.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && !providerHostEnabled) {
    assertions = [
      {
        assertion = lib.versionAtLeast kernelVersion "6.6";
        message = "NVIDIA Orin virtualization requires kernel 6.6 or newer; got ${kernelVersion}.";
      }
    ];

    boot.kernelPatches = [
      {
        name = "Orin virtualization kernel configuration";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          PCI_STUB = lib.mkDefault yes;
          VFIO = lib.mkDefault yes;
          VIRTIO_PCI = lib.mkDefault yes;
          VIRTIO_MMIO = lib.mkDefault yes;
          HOTPLUG_PCI = lib.mkDefault yes;
          PCI_DEBUG = lib.mkDefault yes;
          PCI_HOST_GENERIC = lib.mkDefault yes;
          VFIO_IOMMU_TYPE1 = lib.mkDefault yes;
          HOTPLUG_PCI_ACPI = lib.mkDefault yes;
          PCI_HOST_COMMON = lib.mkDefault yes;
          VFIO_PLATFORM = lib.mkDefault yes;
          TEGRA_BPMP_GUEST_PROXY = lib.mkDefault no;
          TEGRA_BPMP_HOST_PROXY = lib.mkDefault no;
        };
      }
      {
        name = "vfio-platform optional reset";
        patch = "${support}/patches/linux/bpmp/0002-vfio_platform-reset-required-false.patch";
      }
      {
        name = "BPMP virtualization proxy drivers";
        patch = cfg.sourcesPatch;
      }
      {
        name = "BPMP virtualization core hooks";
        patch = "${support}/patches/linux/bpmp/0001-bpmp-virt-hooks.patch";
      }
    ];

    boot.kernelParams = [
      "vfio_iommu_type1.allow_unsafe_interrupts=1"
      "arm-smmu.disable_bypass=0"
    ];
  };
}
