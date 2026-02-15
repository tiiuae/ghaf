# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.ghaf.services.fprint;
in
{
  _file = ./fprint.nix;

  options.ghaf.services.fprint = {
    enable = mkEnableOption "Enable fingerprint reader support";
  };

  config = mkIf cfg.enable {
    # Enable service and package for fingerprint reader
    services.fprintd.enable = true;
    environment.systemPackages = [ pkgs.fprintd ];

    ghaf = {
      systemd.withPolkit = true;
      security.audit.extraRules = [
        "-w /var/lib/fprint/ -p wa -k fprint"
      ];
    }
    // lib.optionalAttrs config.ghaf.storagevm.enable {
      # Persistent storage
      storagevm.directories = [
        {
          directory = "/var/lib/fprint";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    # Enable polkit and add rules
    security = {
      polkit = {
        enable = true;
        debug = true;
        # Polkit rules for fingerprint reader
        extraConfig = ''
          // Allow user to verify fingerprints
          polkit.addRule(function(action, subject) {
          if (action.id == "net.reactivated.fprint.device.verify" &&
              subject.isInGroup ("users")) {
            return polkit.Result.YES;
            }
          });
          // Allow user to enroll fingerprints
          polkit.addRule(function(action, subject) {
          if (action.id == "net.reactivated.fprint.device.enroll" &&
              subject.isInGroup ("users")) {
            return polkit.Result.YES;
            }
          });
        '';
      };
    };
  };
}
