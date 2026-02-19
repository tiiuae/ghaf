# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf mkMerge;
  useGivc = config.ghaf.givc.enable;
  cfg = config.ghaf.services.timezone;

  ghafTimezoneHandler = pkgs.writeShellApplication {
    name = "ghaf-timezone-handler";
    runtimeInputs = with pkgs; [
      systemd
      givc-cli
    ];
    text = ''
      TZ_FILE="/etc/localtime"
      [ -f $TZ_FILE ] || exit 0

      TZ=$(timedatectl show | grep '^Timezone=' | cut -d= -f2-)

      echo "New timezone detected: $TZ"
      givc-cli ${config.ghaf.givc.cliArgs} set-timezone "$TZ" || echo "Failed to set timezone to $TZ"
    '';
  };
in
{
  _file = ./timezone.nix;

  options.ghaf.services.timezone = {
    enable = mkEnableOption ''
      runtime management of timezone settings.

      When enabled, system timezone can be changed imperatively
      without rebuilding the system configuration.
    '';
    propagate = mkEnableOption ''
      propagating runtime timezone changes from the system
      to the host using `givc`.

      This keeps the host locale in sync with user-selected
      desktop locale settings.
    '';
  };

  config = mkIf cfg.enable (mkMerge [
    {

      assertions = [
        {
          assertion = cfg.propagate -> useGivc;
          message = "Enabling timezone settings propagation ('ghaf.services.timezone.enable') requires GIVC to be enabled in the system.";
        }
      ];

      # Allow runtime timezone management
      time.timeZone = null;
    }

    (mkIf cfg.propagate {
      systemd = {
        timers.ghaf-timezone-listener = {
          description = "Ghaf Timezone Listener";
          timerConfig = {
            OnTimezoneChange = true;
            Unit = "ghaf-timezone-forwarder.service";
          };
          wantedBy = [ "graphical.target" ];
        };
        services.ghaf-timezone-forwarder = {
          description = "Ghaf Timezone Forwarder";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe ghafTimezoneHandler}";
          };
        };
      };

      security.polkit = {
        enable = true;
        extraConfig = ''
          // Allow users to set timezone (needed for COSMIC Settings)
          polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.timedate1.set-timezone" &&
              subject.isInGroup ("users")) {
            return polkit.Result.YES;
            }
          });
        '';
      };
    })
  ]);
}
