# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.x86_64.common;
in
{
  options.ghaf.hardware.x86_64.common = {
    enable = lib.mkEnableOption "Common x86 configs";
  };

  config = lib.mkIf cfg.enable {

    # Add this for x86_64 hosts to be able to more generically support hardware.
    # For example Intel NUC 11's graphics card needs this in order to be able to
    # properly provide acceleration.
    hardware.enableRedistributableFirmware = true;
    hardware.enableAllFirmware = true;

    boot = {
      # Enable normal Linux console on the display, and QR code kernel panic
      kernelParams = [
        "console=tty0"
        "console=ttyUSB0,115200"
        "drm.panic_screen=qr_code"
      ];

      # To enable installation of ghaf into NVMe drives
      initrd.availableKernelModules = [
        "nvme"
        "uas"
        "fake_battery"
      ];
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      kernelPackages = pkgs.linuxPackages;

      extraModulePackages = [
        (config.boot.kernelPackages.callPackage ../../../packages/kernel/modules/fake-battery { })
      ];
    };
  };
}
