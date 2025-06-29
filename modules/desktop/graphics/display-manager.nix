# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.display-manager;
  inherit (lib)
    mkIf
    mkOption
    types
    ;

  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  logindSuspendListener = pkgs.writeShellApplication {
    name = "logind-suspend-listener";
    runtimeInputs = [
      pkgs.dbus
      pkgs.systemd
      ghaf-powercontrol
    ];
    text = ''
      dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" | \
        while read -r line; do
          if echo "$line" | grep -q "boolean true"; then
            echo "Found prepare for sleep signal"
            ghaf-powercontrol turn-off-displays
          elif echo "$line" | grep -q "boolean false"; then
            echo "Found wake up signal"
            ghaf-powercontrol wakeup
          fi
        done
    '';
  };
in
{
  options.ghaf.graphics.display-manager = {
    enable = mkOption {
      description = ''
        Manage displays during suspend and wakeup operations. This will turn off displays
        when the system is suspended and turn them back on when the system is woken up.
      '';
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    systemd.services.logind-suspend-listener = {
      enable = true;
      description = "Ghaf logind suspend listener";
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5";
        ExecStart = "${lib.getExe logindSuspendListener}";
      };
      partOf = [ "graphical.target" ];
      wantedBy = [ "graphical.target" ];
    };
  };
}
