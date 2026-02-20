# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Thor AGX hardware configuration
#
{ lib, ... }:
{
  ghaf.hardware.nvidia.thor = {
    enable = true;
    somType = "agx";
    carrierBoard = "devkit";
  };

  hardware = {
    # Thor device tree: tegra264-p4071-0000+p3834-0008-nv.dtb
    # p4071 = carrier board (devkit), p3834 = SOM
    # deviceTree.name = "tegra264-p4071-0000+p3834-0008-nv.dtb";

    nvidia-jetpack = {
      enable = true;
      som = "thor-agx";
      carrierBoard = "devkit";
      modesetting.enable = true;

      # Thor uses external NVMe for rootfs (no eMMC)
      firmware.initialBootOrder = [ "nvme" ];
      flashScriptOverrides.flashArgs = lib.mkForce [
        "jetson-agx-thor-devkit"
        "external"
      ];
      # };
      # firmware.uefi = {
      #   logo = "${pkgs.ghaf-artwork}/1600px-Ghaf_logo.svg";
      # };
    };
  };
}
