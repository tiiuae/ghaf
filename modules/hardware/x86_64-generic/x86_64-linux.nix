# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./x86_64-linux.nix;

  options.ghaf.hardware.x86_64.common = {
    enable = lib.mkEnableOption "Common x86 configs";
  };

  config = lib.mkIf cfg.enable {
    # Enable memory wiping for x86_64 host platforms
    ghaf.host.kernel.memory-wipe.enable = lib.mkDefault true;

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

      extraModulePackages = [
        (config.boot.kernelPackages.callPackage ./kernel/modules/fake-battery { })
      ];
    };
  };
}
