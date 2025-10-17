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
  inherit (lib) mkEnableOption mkIf;
  useGivc = config.ghaf.givc.enable;
  cfg = config.ghaf.services.timezone;

  ghafTimezoneListener = pkgs.writeShellApplication {
    name = "ghaf-timezone-listener";
    runtimeInputs = with pkgs; [
      dbus
      systemd
      givc-cli
      gawk
    ];
    # timedate1 is a system service, this script should be run as a system service
    # Propagate timezone changes from the gui-vm to givc-cli
    text = ''
      # shellcheck disable=SC2016
      busctl monitor org.freedesktop.timedate1 | stdbuf -oL awk '
        /^$/ {
          if (in_block && found_timezone && timezone != "") {
            print timezone
          }
          in_block = 0;
          found_timezone = 0;
          timezone = "";
        }
        /PropertiesChanged/ {
          in_block = 1;
        }
        /"Timezone"/ {
          if (in_block) found_timezone = 1;
        }
        /STRING/ {
          if (found_timezone && timezone == "" && match($0, /"[^"]+"/)) {
            tz = substr($0, RSTART+1, RLENGTH-2);
            if (tz != "Timezone") timezone = tz;
          }
      }' | while read -r tz; do
             echo "New timezone detected: $tz"
             givc-cli ${config.ghaf.givc.cliArgs} set-timezone "$tz" || echo "Failed to set timezone to $tz"
           done
    '';
  };
in
{
  options.ghaf.services.timezone = {
    enable = mkEnableOption "Propagate timezone changes from the system to givc-cli";
  };

  config = mkIf (cfg.enable && useGivc) {
    systemd.services = {
      ghaf-timezone-listener = {
        enable = true;
        description = "Ghaf timezone listener";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe ghafTimezoneListener}";
        };
        partOf = [ "graphical.target" ];
        wantedBy = [ "graphical.target" ];
      };
    };
  };
}
