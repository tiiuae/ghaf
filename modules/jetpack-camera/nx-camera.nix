# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin.nx;
in {
  options.ghaf.hardware.nvidia.orin.nx.camera =
    lib.mkEnableOption
    "Enabling E-con camera driver for Orin NX ";

  config = lib.mkIf cfg.camera {
    # Orin NX camera driver
    boot.modprobeConfig.enable = true;
    boot.kernelPatches = [
      #Toshiba - Alvium Kernel Patch
      {
        name = "nx-camera-kernel-patch";
        # This patch is for Toshiba HDMI camera and Alvium CSI2 camera patch
        patch = ./alvium_toshiba_kernel.patch;
        # For Alvium Kernel configuration changes
        extraStructuredConfig = with lib.kernel; {
          LOCALVERSION_AUTO = yes;
          V4L = yes;
          I2C = yes;
          VIDEO_V4L2 = yes;
          VIDEO_V4L2_SUBDEV_API = yes;
          FB_EFI = lib.mkForce unset;
          PCI_SERIAL_CH384 = lib.mkForce unset;
          SENSORS_F75308 = lib.mkForce unset;
          USB_NET_CDC_MBIM = lib.mkForce unset;
          TEGRA23X_OC_EVENT = lib.mkForce unset;
          TEGRA19X_OC_EVENT = lib.mkForce unset;
          VIDEO_ECAM = lib.mkForce unset;
          VIDEO_AVT_CSI2 = module;
          VIDEO_TC358743 = module;
          NV_VIDEO_HAWK_OWL = lib.mkForce unset;
          HID_SHIELD_REMOTE = lib.mkForce unset;
          USB_WDM = lib.mkForce module;
          TYPEC_FUSB301 = lib.mkForce unset;
          ISO9660_FS = lib.mkForce unset;
          SECURITY_DMESG_RESTRICT = lib.mkForce unset;
        };
      }
      #Toshiba - Alvium DTB Patch
      {
        name = "nx-camera-dtb-patch";
        # This patch is for Toshiba HDMI camera and Alvium CSI2 camera patch
        patch = ./alvium_toshiba_dtb.patch;
      }
    ];

    boot.extraModprobeConfig = ''
      # example settings
      options tc358743 modeset=1
      options avt_csi2 modeset=1
    '';
  };
}
