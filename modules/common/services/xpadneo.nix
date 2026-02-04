# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.xpadneo;
  inherit (lib) mkIf mkEnableOption;
  bluetoothUser = config.ghaf.services.bluetooth.user;
in
{
  _file = ./xpadneo.nix;

  options.ghaf.services.xpadneo = {
    enable = mkEnableOption "The support for wireless Xbox Controllers";
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = config.ghaf.services.bluetooth.enable;
        message = "Please enable ghaf bluetooth service to use xpadneo module";
      }
    ];

    # Enable the xpadneo driver for Xbox wireless controllers
    hardware.xpadneo = {
      enable = true;
    };

    hardware.bluetooth = {
      settings.General = {
        Privacy = "device";
      };
    };

    boot.initrd.kernelModules = [
      "uhid"
      "hid-xpadneo"
    ];

    services.udev.extraRules = ''
      KERNEL=="uhid", SUBSYSTEM=="misc", GROUP="${bluetoothUser}"
    '';
  };
}
