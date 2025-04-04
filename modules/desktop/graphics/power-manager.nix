# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# This module overrides logind power management using ghaf-powercontrol.
# The specific operations overriden are:
# - Suspend
# - Shutdown
# - Reboot
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.power-manager;
  inherit (lib)
    mkIf
    mkOption
    types
    ;

  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  logindSuspendListener = pkgs.writeShellApplication {
    # This listener monitors systemd's suspend signals and delays the suspend process
    # While the process is delayed, we use ghaf-powercontrol to handle the suspend operation instead
    # TODO: Investigate if suspension can be cancelled entirely if caught. Some notes on that:
    # - `--mode=block` does not work, as it will block suspension entirely and no signal will be sent
    # - `--mode=delay` works, but the system will still suspend after the delay
    name = "logind-suspend-listener";
    runtimeInputs = [
      pkgs.dbus
      pkgs.systemd
      ghaf-powercontrol
    ];
    text = ''
      systemd-inhibit --what=sleep --who="ghaf-powercontrol" \
        --why="Handling ghaf suspend" --mode=delay \
          dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" | \
            while read -r line; do
              if echo "$line" | grep -q "boolean true"; then
                echo "Found prepare for sleep signal"
                echo "Suspending via ghaf-powercontrol"
                ghaf-powercontrol suspend
              fi
            done
    '';
  };

  logindShutdownListener = pkgs.writeShellApplication {
    # This listener monitors systemd's shutdown/reboot signals and delays the process
    # While the process is delayed, we use ghaf-powercontrol to handle the shutdown/reboot operation instead
    name = "logind-shutdown-listener";
    runtimeInputs = [
      pkgs.dbus
      pkgs.systemd
      ghaf-powercontrol
    ];
    text = ''
      systemd-inhibit --what=shutdown --who="ghaf-powercontrol" \
        --why="Handling ghaf shutdown/reboot" --mode=delay \
          dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForShutdownWithMetadata'" | \
            while read -r line; do
              if echo "$line" | grep -q "boolean true"; then
                echo "Found prepare for shutdown signal. Checking type..."
                while read -r subline; do
                    if echo "$subline" | grep -q "reboot"; then
                        echo "Found type: reboot"
                        echo "Rebooting via ghaf-powercontrol"
                        ghaf-powercontrol reboot
                    elif echo "$subline" | grep -q "poweroff"; then
                        echo "Found type: power-off"
                        echo "Powering off via ghaf-powercontrol"
                        ghaf-powercontrol poweroff
                    fi
                done
              fi
            done
    '';
  };
in
{
  options.ghaf.graphics.power-manager = {
    enable = mkOption {
      description = ''
        Override logind power management using ghaf-powercontrol
      '';
      type = types.bool;
      default = false;
    };
    enableSuspendListener = mkOption {
      description = ''
        Enable the suspend signal listener service
      '';
      type = types.bool;
      default = true;
    };

    enableShutdownListener = mkOption {
      description = ''
        Enable the shutdown/reboot signal listener service
      '';
      type = types.bool;
      default = true;
    };
  };

  config = mkIf cfg.enable {
    systemd.services = {
      logind-shutdown-listener = mkIf cfg.enableShutdownListener {
        enable = true;
        description = "Ghaf logind shutdown listener";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5";
          ExecStart = "${lib.getExe logindShutdownListener}";
        };
        partOf = [ "graphical.target" ];
        wantedBy = [ "graphical.target" ];
      };

      logind-suspend-listener = mkIf cfg.enableSuspendListener {
        # Currently system continues to suspend even after ghaf-powercontrol suspend is called
        # If running on host:
        #   - Might result in two suspension requests in a row
        # If running on VM:
        #   - Will result in `ghaf-powercontrol suspend` first. If woken up see next point
        #   - Will result in a non-functional VM suspend, which gets cancelled almost immediately
        #   - End result - System suspends, wakes up, attempts to suspend again but wakes up immediately
        # NOTE:
        # As a system service, this will run as root
        # This means ghaf-powercontrol will run as root and therefore fail to
        # find and turn off the display as part of the suspension procedures
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
  };
}
