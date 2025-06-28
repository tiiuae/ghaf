# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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
          if (in_block && found_locale && locale != "") {
            print locale";"language
          }
          in_block = 0;
          found_locale = 0;
          locale = "";
          language = "";
        }
        /PropertiesChanged/ {
          in_block = 1;
        }
        /"Locale"/ {
          if (in_block) found_locale = 1;
        }
        /STRING/ {
          if (found_locale && locale == "") {
            match($0, /"LC_IDENTIFICATION[^"]+"/)
            if (RSTART) {
              unquoted = substr($0, RSTART+1, RLENGTH-2)
              split(unquoted, parts, "LC_IDENTIFICATION=")
              if (length(parts) > 1) {
                str = parts[2]
                locale = str
              }
            }
            match($0, /"LANG[^"]+"/)
            if (RSTART) {
              unquoted = substr($0, RSTART+1, RLENGTH-2)
              split(unquoted, parts, "LANG=")
              if (length(parts) > 1) {
                str = parts[2]
                language = str
              }
            }
          }
        }' | while IFS= read -r line; do
             IFS=';' read -r -a locale <<< "$line"
             echo "New locale detected: ''${locale[0]}"
             echo "Setting locale to ''${locale[0]}"
             givc-cli ${config.ghaf.givc.cliArgs} set-locale "''${locale[0]}" || echo "Failed to set locale to ''${locale[0]}"
             if [ -z "''${locale[1]}" ]; then
               echo "No language set, skipping language change."
               continue
             fi
             # echo "Setting language to ''${locale[1]}"
             # givc-cli ${config.ghaf.givc.cliArgs} set-locale "LANG=''${locale[1]}" || echo "Failed to set language to ''${locale[1]}"
             echo "givc does not support locale value assignments, skipping language change."
           done
    '';
  };
in
{
  options.ghaf.services.locale = {
    enable = mkEnableOption "Propagate locale changes from the system to givc-cli";
  };

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
  };
}
