# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.login-manager;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  greeterUser = "cosmic-greeter";
in
{
  options.ghaf.graphics.login-manager = {
    enable = mkEnableOption "Ghaf login manager config using greetd";
    failLock = {
      enable = mkEnableOption ''
        Account locking after repeated failed login attempts.
        When activated, the system will temporarily lock accounts that
        exceed the maximum allowed authentication failures.
      '';
      maxTries = mkOption {
        description = ''
          Defines the number of authentication failures required before locking the account.
          Key details:
            1 authentication failure = 5 consecutive failed login attempts
            The system aggregates 5 incorrect password attempts into one recorded authentication failure.
            When maxTries = 2, locking occurs after:
            2 authentication failures × 5 attempts each = 10 total failed login attempts
          The counter resets after successful authentication
        '';
        type = types.int;
        default = 2;
      };
    };
  };

  config = mkIf cfg.enable {
    # Ensure there is always a backlight brightness value to restore from on boot
    # ghaf-powercontrol will store the value here via systemd-backlight.service
    ghaf = lib.optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
      storagevm.directories = [
        {
          directory = "/var/lib/systemd/backlight";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    systemd.services.greetd.serviceConfig = {
      RestartSec = "5";
    };

    users.users.${greeterUser}.extraGroups = [ "video" ];

    # Needed for the greeter to query systemd-homed / sssd users correctly
    systemd.services.cosmic-greeter-daemon.environment.LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (
      [ pkgs.systemd ] ++ lib.optionals config.ghaf.services.sssd.enable [ pkgs.sssd ]
    )}";

    security.pam.services = {
      cosmic-greeter = {
        rules = {
          auth = {
            systemd_home.order = 11399; # Re-order to allow either password _or_ fingerprint on lockscreen
            unix.settings.use_first_pass = !config.ghaf.services.sssd.enable;
            fprintd.args = [ "maxtries=3" ];
          };
        };
      };
      greetd = {
        fprintAuth = false; # User needs to enter password to decrypt home on login
        rules = {
          auth = {
            systemd_home.order = 11399; # Re-order to allow either password _or_ fingerprint on lockscreen
            unix.settings.use_first_pass = !config.ghaf.services.sssd.enable;
            fprintd.args = [ "maxtries=3" ];

            # This should precede other auth rules e.g. pam_sss.so (pam module for SSSD)
            faillock_preauth = mkIf cfg.failLock.enable {
              enable = true;
              control = "required";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_faillock.so";
              order = 11300;
              args = [
                "preauth"
                "audit"
                "unlock_time=900"
                "deny=${toString cfg.failLock.maxTries}"
              ];
            };

            # This should follow auth rules but should come before pam_deny.so
            faillock_authfail = mkIf cfg.failLock.enable {
              enable = true;
              control = "[default=die]";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_faillock.so";
              order = 12399;
              args = [
                "authfail"
                "audit"
                "unlock_time=900"
                "deny=${toString cfg.failLock.maxTries}"
              ];
            };
          };
          account = {
            faillock = mkIf cfg.failLock.enable {
              enable = true;
              control = "required";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_faillock.so";
              order = 10600;
            };
            deny_admin = {
              enable = !config.ghaf.users.admin.enableUILogin;
              control = "requisite";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_succeed_if.so";
              order = 10700;
              args = [
                "user"
                "!="
                "${config.ghaf.users.admin.name}"
              ];
            };
          };
        };
      };
    };
  };
}
