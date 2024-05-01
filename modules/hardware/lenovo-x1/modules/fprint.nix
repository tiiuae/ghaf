# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.hardware.fprint;
in
  with lib; {
    options.ghaf.hardware.fprint = {
      enable = mkEnableOption "Enable fingerprint reader support";
      qemuExtraArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Extra arguments to pass to Qemu when enabling the fingerprint reader.
          This is useful for passing USB device information to Qemu.
        '';
      };
      extraConfigurations = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = ''
          Extra configurations to enable when enabling the fingerprint reader.
          This is useful for enabling services and packages related to the fingerprint reader.
        '';
      };
    };

    config = mkIf cfg.enable {
      ghaf.hardware.fprint = {
        qemuExtraArgs = [
          # Fingerprint reader
          "-device"
          "qemu-xhci"
          "-device"
          "usb-host,hostbus=3,hostport=6"
        ];

        extraConfigurations = {
          # Enable service and package for fingerprint reader
          services.fprintd.enable = true;
          environment.systemPackages = with pkgs; [fprintd];

          # Enable polkit and add rules
          ghaf.systemd.withPolkit = true;
          security = {
            polkit = {
              enable = true;
              debug = true;
              # Polkit rules for fingerprint reader
              extraConfig = ''
                // Allow user to verify fingerprints
                polkit.addRule(function(action, subject) {
                if (action.id == "net.reactivated.fprint.device.verify" &&
                    subject.user == "ghaf") {
                  return polkit.Result.YES;
                  }
                });
                // Allow user to enroll fingerprints
                polkit.addRule(function(action, subject) {
                if (action.id == "net.reactivated.fprint.device.enroll" &&
                    subject.user == "ghaf") {
                  return polkit.Result.YES;
                  }
                });
              '';
            };
            # PAM rules for swaylock fingerprint reader
            pam.services = {
              swaylock.text = ''
                # Account management.
                account required pam_unix.so

                # Authentication management.
                auth sufficient pam_unix.so likeauth try_first_pass
                auth sufficient ${pkgs.fprintd}/lib/security/pam_fprintd.so
                auth required pam_deny.so

                # Password management.
                password sufficient pam_unix.so nullok sha512

                # Session management.
                session required pam_env.so conffile=/etc/pam/environment readenv=0
                session required pam_unix.so
              '';
            };
          };
        };
      };
    };
  }
