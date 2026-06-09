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
  _file = ./login-manager.nix;

  options.ghaf.graphics.login-manager = {
    enable = mkEnableOption "Ghaf login manager config using greetd";
    # PAM faillock module configuration
    failLock = {
      enable = mkEnableOption ''
        Account locking after repeated failed login attempts.
        When activated, the system will temporarily lock accounts that
        exceed the maximum allowed authentication failures.
      '';

      maxTries = mkOption {
        description = ''
          Defines the maximum number of consecutive failed authentication
          attempts allowed before the account is temporarily locked.

          Key details:
            - Each incorrect password submission increments the failure counter by one.
            - Reaching this configured threshold immediately triggers the account lock.
            - The internal failure counter resets upon a successful login.
        '';
        type = types.int;
        default = 5;
      };
    };
  };

  config = mkIf cfg.enable {
    # Ensure there is always a backlight brightness value to restore from on boot
    # ghaf-powercontrol will store the value here via systemd-backlight.service
    ghaf.storagevm.directories = lib.mkIf config.ghaf.storagevm.enable [
      {
        directory = "/var/lib/systemd/backlight";
        user = "root";
        group = "root";
        mode = "0700";
      }
    ];

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
          account = {
            # When homed auth was used, PAM_AUTHTOK holds the real password and
            # systemd_home account succeeds → done. When fingerprint was used,
            # PAM_AUTHTOK is unset and systemd_home fails → fall through to permit.
            systemd_home.control = lib.mkForce "[success=done default=ignore]";
            permit = {
              enable = true;
              control = "[success=done default=ignore]";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_permit.so";
              order = 10900; # after systemd_home (10800), before unix (11000)
            };
          };
          auth = {
            unix.settings.use_first_pass = !config.ghaf.services.sssd.enable;
            fprintd.args = [ "max-tries=3" "timeout=-1" ];
          };
        };
      };
      greetd = {
        fprintAuth = false; # User needs to enter password to decrypt home on login
        rules = {
          auth = {
            unix.settings.use_first_pass = !config.ghaf.services.sssd.enable;

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
