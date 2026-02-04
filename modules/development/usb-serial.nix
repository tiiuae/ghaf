# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.development.usb-serial;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./usb-serial.nix;

  options.ghaf.development.usb-serial = {
    enable = mkEnableOption "Usb-Serial";
  };

  #TODO Should this be alos bound to only x86?
  config = mkIf cfg.enable {
    services.getty.extraArgs = [ "115200" ];
    systemd.services."autovt@ttyUSB0".enable = true;

    # ttyUSB0 service is active as soon as corresponding device appears
    services.udev.extraRules = ''
      SUBSYSTEM=="tty", KERNEL=="ttyUSB0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="autovt@ttyUSB0.service"
    '';
  };
}
