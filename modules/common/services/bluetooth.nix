# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.services.bluetooth;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.ghaf.services.bluetooth = {
    enable = mkEnableOption "Bluetooth configurations";
  };
  config = mkIf cfg.enable {
    hardware.bluetooth = {
      enable = true;
    };

    # Polkit rules for blueman
    ghaf.systemd.withPolkit = true;
    security.polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if ((action.id == "org.blueman.network.setup" ||
              action.id == "org.blueman.dhcp.client" ||
              action.id == "org.blueman.rfkill.setstate" ||
              action.id == "org.blueman.pppd.pppconnect") &&
              subject.user == "ghaf") {
              return polkit.Result.YES;
          }
        });
      '';
    };

    systemd.tmpfiles.rules = [ "f /var/lib/systemd/linger/${config.ghaf.users.accounts.user}" ];
  };
}
