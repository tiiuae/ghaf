# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin.agx;
in {
  options.ghaf.hardware.nvidia.orin.agx.camera =
    lib.mkEnableOption
    "Enabling E-con camera driver for Orin AGX ";
  config = lib.mkIf cfg.camera {
    # Orin AGX camera driver

    boot.kernelPatches = [
      #Toshiba - Alvium Kernel Patch
      {
        name = "nx-camera-kernel-patch";
        # This patch is for Toshiba HDMI camera and Alvium CSI2 camera patch
        patch = ./alvium_toshiba_kernel.patch;
        # For Alvium Kernel configuration changes
        extraStructuredConfig = with lib.kernel; {
          CONFIG_LOCALVERSION_AUTO = yes;
          CONFIG_FB_EFI = lib.mkForce unset;
          CONFIG_PCI_SERIAL_CH384 = lib.mkForce unset;
          CONFIG_SENSORS_F75308 = lib.mkForce unset;
          CONFIG_USB_NET_CDC_MBIM = lib.mkForce unset;
          CONFIG_TEGRA23X_OC_EVENT = lib.mkForce unset;
          CONFIG_TEGRA19X_OC_EVENT = lib.mkForce unset;
          CONFIG_VIDEO_ECAM = lib.mkForce unset;
          CONFIG_VIDEO_AVT_CSI2 = lib.mkForce unset;
          CONFIG_NV_VIDEO_HAWK_OWL = lib.mkForce unset;
          CONFIG_HID_SHIELD_REMOTE = lib.mkForce unset;
          CONFIG_USB_WDM = module;
          CONFIG_TYPEC_FUSB301 = lib.mkForce unset;
          CONFIG_ISO9660_FS = lib.mkForce unset;
          CONFIG_SECURITY_DMESG_RESTRICT = lib.mkForce unset;
        };
      }
      #Toshiba - Alvium DTB Patch
      {
        name = "nx-camera-dtb-patch";
        # This patch is for Toshiba HDMI camera and Alvium CSI2 camera patch
        patch = ./alvium_toshiba_dtb.patch;
      }
    ];
  };
}
