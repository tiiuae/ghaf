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
  cfg = config.ghaf.services.locale;

  ghafLocaleListener = pkgs.writeShellApplication {
    name = "ghaf-locale-listener";
    runtimeInputs = with pkgs; [
      dbus
      systemd
      givc-cli
      gawk
    ];
    # locale1 is a system service, this script should be run as a system service
    # Propagate locale changes from the gui-vm to givc-cli
    text = ''
      # shellcheck disable=SC2016
      busctl monitor org.freedesktop.locale1 | stdbuf -oL awk '
        /^$/ {
          if (in_block && found_locale && locale_str != "") {
            print locale_str
          }
          in_block = 0
          found_locale = 0
          locale_str = ""
        }
        /PropertiesChanged/ { in_block = 1 }
        /"Locale"/ {
          if (in_block) found_locale = 1
        }
        /^ *STRING/ {
          if (found_locale && match($0, /"[^"]+"/)) {
            line = substr($0, RSTART+1, RLENGTH-2)
            if (line ~ /^(LANG|LC_[^=]+)=/) {
              locale_str = (locale_str == "" ? line : locale_str ";" line)
            }
          }
        }' |  while IFS= read -r line; do
              locale_settings="''${line//;/ }"
              echo "Applying locale settings: ''$line"

              echo "''$locale_settings" | xargs givc-cli ${config.ghaf.givc.cliArgs} set-locale || echo "Failed to apply locale settings: \"''$locale_settings\""
              done
    '';
  };
in
{
  _file = ./locale.nix;

  options.ghaf.services.locale.enable =
    mkEnableOption "Propagate locale changes from the system to givc-cli";

  config = mkIf (cfg.enable && useGivc) {
    systemd.services = {
      ghaf-locale-listener = {
        enable = true;
        description = "Ghaf locale listener";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe ghafLocaleListener}";
        };
        partOf = [ "graphical.target" ];
        wantedBy = [ "graphical.target" ];
      };
    };

    security.polkit = {
      enable = true;
      extraConfig = ''
        // Allow users to set locale (needed for COSMIC Settings)
        polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.locale1.set-locale" &&
            subject.isInGroup ("users")) {
          return polkit.Result.YES;
          }
        });
      '';
    };
  };
}
