# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.services.fprint;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.ghaf.services.fprint = {
    enable = mkEnableOption "Enable fingerprint reader support";
    qemuExtraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = ''
        Extra arguments to pass to qemu when enabling the fingerprint reader.
      '';
    };
    extraConfigurations = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = ''
        Extra configurations when enabling the fingerprint reader in a guest.
      '';
    };
  };

  config = mkIf cfg.enable {
    ghaf.services.fprint = {
      # Use qemu arguments generated for the device
      qemuExtraArgs = config.ghaf.hardware.usb.internal.qemuExtraArgs.fprint-reader;

      extraConfigurations = {
        # Enable service and package for fingerprint reader
        services.fprintd.enable = true;
        environment.systemPackages = [pkgs.fprintd];

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
    # Enable host store for fingerprints
    ghaf.services.storage.shares = [
      {
        tag = "fprint-store";
        host-path = "/var/lib/fprint";
        vm-path = "/var/lib/fprint";
        target-vm = "gui-vm";
        target-owner = "root";
        target-group = "root";
        target-permissions = "600";
        target-service = "fprintd.service";
      }
    ];
  };
}
