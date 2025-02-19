# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
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
    nixpkgs.hostPlatform.system = "x86_64-linux";

    # Increase the support for different devices by allowing the use
    # of proprietary drivers from the respective vendors
    nixpkgs.config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "jitsi-meet-1.0.8043"
      ];
    };

    # Add this for x86_64 hosts to be able to more generically support hardware.
    # For example Intel NUC 11's graphics card needs this in order to be able to
    # properly provide acceleration.
    hardware.enableRedistributableFirmware = true;
    hardware.enableAllFirmware = true;

    boot = {
      # Enable normal Linux console on the display
      kernelParams = [ "console=tty0" ];

      # To enable installation of ghaf into NVMe drives
      initrd.availableKernelModules = [
        "nvme"
        "uas"
      ];
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };
    };
  };
}
