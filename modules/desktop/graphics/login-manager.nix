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

    # The panel arrives at 0, and with nothing saved to restore
    # systemd-backlight only lifts it to its 1% floor. The host carries the same
    # rule from when it owned the display; the GUI VM holds the eDP backlight now
    # and needs its own.
    #
    # A floor, not an override: systemd-backlight's `load` runs after udev, so a
    # remembered value still wins.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="backlight", ATTR{brightness}="$attr{max_brightness}"
    '';

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
            # faillock and deny_admin must run before systemd_home/permit can
            # short-circuit the account stack with success=done.
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
            permit = {
              enable = true;
              control = "[success=done default=ignore]";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_permit.so";
              order = 10900; # after systemd_home (10800), before unix (11000)
            };
          };
          auth = {
            unix.settings.use_first_pass = !config.ghaf.services.sssd.enable;
            fprintd.args = [
              "max-tries=3"
              "timeout=-1"
            ];

            # Mirror the greetd faillock rules: cosmic-greeter performs the
            # real unix/fprintd authentication for login and unlock, so the
            # lockout policy must apply on this path too.
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
        };
      };
      # nixpkgs' greetd module (upstream f941d78c5a, "nixos/greetd: substack login
      # in PAM") sets `useDefaultRules = false` and reduces greetd's whole stack to
      # `substack login` / `include login` at order 10100. greetd therefore has no
      # unix, fprintd or deny rules of its own any more:
      #   - `rules.auth.unix.*` here would define a rule with no order/control and
      #     abort evaluation,
      #   - `fprintAuth = false` here would be a silent no-op.
      # Anything about *how* the password is checked now belongs on `login`, below.
      # Only the rules that are genuinely greetd-specific stay on greetd.
      login = {
        fprintAuth = false; # user must type their password to decrypt home

        # The faillock pair has to live in login's *own* stack, next to the
        # pam_unix rule it wraps -- not in greetd's stack around the substack.
        # `sufficient` short-circuits only to the end of the stack level it sits
        # in (libpam pam_dispatch.c, the `decision_made` loop skips handlers
        # while `stack_level >= ` the current one), so an authfail rule placed
        # after `substack login` still runs when login's `sufficient pam_unix`
        # already succeeded. Two ways that bites:
        #   - pam_setcred: greetd's greeter session never calls pam_authenticate,
        #     so pam_unix returns success from setcred, the substack ends, and
        #     authfail runs anyway. `[default=die]` maps *every* return code
        #     (pam_misc.c `_pam_set_default_control` fills each unset slot),
        #     success included, so the stack dies and libpam's sanity check turns
        #     the result into PAM_PERM_DENIED -> "pam_setcred: PERM_DENIED" and
        #     greetd never starts the greeter.
        #   - a correct password: authfail runs on the success path, returns
        #     PAM_IGNORE *and* writes a failure tally, so logins fail and the
        #     account locks itself after maxTries successful attempts.
        # Placed back in the flat stack the `sufficient pam_unix` hit skips both,
        # which is how this behaved before the upstream substack change.
        rules.auth = {
          # Before unix (11700) so a locked account is rejected up front.
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

          # After unix (11700) so it observes the auth result, but before
          # deny (12500) so a failure is recorded before the stack is denied.
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
      };

      greetd = {
        rules = {
          # Both of these must precede `account include login` (order 10100).
          # `include` inlines the included rules at the *same* stack level, so
          # login's `account sufficient pam_systemd_home` short-circuits the
          # whole chain for systemd-homed users -- skipping everything ordered
          # after it, deny_admin included. Before the upstream substack change
          # these sat at 10600/10700, ahead of the default systemd_home rule at
          # 10800; the include moved that rule to the front of the chain, so
          # they have to move ahead of the include to keep running.
          account = {
            faillock = mkIf cfg.failLock.enable {
              enable = true;
              control = "required";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_faillock.so";
              order = 10010;
            };
            deny_admin = {
              enable = !config.ghaf.users.admin.enableUILogin;
              control = "requisite";
              modulePath = "${pkgs.linux-pam}/lib/security/pam_succeed_if.so";
              order = 10020;
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
