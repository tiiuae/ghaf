# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.user-provisioning;

  # The account the Robot Framework suite logs in as. Kept in one place because
  # the unit, its exec-condition and the reset helper must all agree on it.
  testUserName = "testuser";
  testUserRealName = "Test User";
  testUserPassword = "testpw";

  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    optionals
    optionalString
    types
    ;

  # Generate JSON provisioning configuration from module options
  provisioningConfig = pkgs.writeText "provisioning.json" (
    builtins.toJSON {

      # Reference existing AD/SSSD configuration
      ad_config =
        let
          domainNames = lib.attrNames config.ghaf.users.active-directory.domains;
          domainConfigs = lib.listToAttrs (
            map (
              domainName:
              let
                domain = config.ghaf.users.active-directory.domains.${domainName} or { };
              in
              lib.nameValuePair domainName {
                domain = domain.ad.domain or "";
                realm = domain.krb5.realm or "";
                ad_server = lib.head domain.ad.controllers or "";
                ldap_server = lib.head domain.ldap.uri or "";
              }
            ) domainNames
          );
        in
        {
          domains = domainConfigs;
        };

      # User setup configuration with sensible defaults
      user_config = optionalAttrs cfg.enableHomed {
        home_size = config.ghaf.users.homedUser.homeSize;
        inherit (config.ghaf.users.homedUser) uid;
        fs_type = config.ghaf.users.homedUser.fsType;
        login_shell = config.ghaf.users.homedUser.loginShell;
        groups = "users${
          optionalString (
            config.ghaf.users.homedUser.extraGroups != [ ]
          ) ",${lib.concatStringsSep "," config.ghaf.users.homedUser.extraGroups}"
        }";
        fido_auth = config.ghaf.users.homedUser.fidoAuth;
      };

      # Storage configuration (if storagevm is available)
      storage = optionalAttrs config.ghaf.storagevm.enable {
        mount_path = config.ghaf.storagevm.mountPath;
      };
    }
  );

  # Deprovisioning script
  deprovisioningScript = pkgs.writeShellApplication {
    name = "user-deprovision";
    runtimeInputs = [
      pkgs.systemd
      pkgs.user-provision
      pkgs.umount
      pkgs.coreutils
    ];
    text = ''
      echo "Starting user deprovisioning..."

      # Make sure users are logged out
      loginctl terminate-seat seat0

      # Remove homed users if enabled
      removed=true
      ${optionalString cfg.enableHomed ''
        SECONDS=0
        while ! user-provision --remove; do
          sleep 2
          if [ $SECONDS -ge 10 ]; then
            # Continue to the AD/keytab cleanup below, but remember the failure:
            # the home areas are still on disk, so this run did not deprovision.
            echo "Timeout: user removal did not complete after 10s" >&2
            removed=false
            break
          fi
        done
      ''}

      # Remove AD parameters if enabled
      ${optionalString cfg.enableAD ''
        rm -rf /var/lib/sssd/*
      ''}
      ${optionalString (cfg.enableAD && config.ghaf.storagevm.enable) ''
        umount /etc/krb5.keytab || true
        rm -f /etc/krb5.keytab || true
        rm -f ${config.ghaf.storagevm.mountPath}/etc/krb5.keytab || true
      ''}

      # Remove provisioning lock. -f because this script runs under `set -e` and
      # the lock is legitimately absent on a device that was never provisioned,
      # which would otherwise fail the unit after the users were already removed.
      rm -f /var/lib/ghaf/user-provisioning.lock

      if [ "$removed" != true ]; then
        echo "Deprovisioning INCOMPLETE: user home areas are still present." >&2
        exit 1
      fi

      echo "User deprovisioning completed."
    '';
  };

  # Exec-condition script for user provisioning service
  execConditionScript = pkgs.writeShellApplication {
    name = "user-provision-exec-condition";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.krb5
    ];
    text =
      optionalString cfg.enableHomed ''
        # Check if homed identity file exists
        if ls /var/lib/systemd/home/*.identity > /dev/null 2>&1; then
          exit 1 # identity file exists, no need for provisioning
        else
          exit 0 # identity file does not exist, needs provisioning
        fi
      ''
      + optionalString cfg.enableAD ''
        # Check if machine is joined to AD domain
        if klist -k /etc/krb5.keytab | grep -qi "host/" 2>/dev/null; then
          exit 1 # machine is enrolled, no need for provisioning
        else
          exit 0 # machine is not enrolled, needs provisioning
        fi
      ''
      + optionalString (!cfg.enableHomed && !cfg.enableAD) ''
        # No provisioning backend enabled: non-zero tells systemd to skip
        # the provisioning service (ExecCondition semantics).
        exit 1
      '';
  };

  # Exec-condition for the *test* user specifically.
  #
  # The condition above asks "has this device been provisioned at all?", which is
  # the right question for the interactive first-boot flow and the wrong one for
  # the test user: on any device that already has a login user it answers "yes"
  # and the test unit is skipped. systemd reports a condition-skipped unit as a
  # successful start, so the test suite saw rc=0 and only discovered the missing
  # account later, as "testuser cannot authenticate".
  testExecConditionScript = pkgs.writeShellApplication {
    name = "user-provision-test-exec-condition";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      if homectl inspect ${testUserName} > /dev/null 2>&1; then
        exit 1 # test user already exists, nothing to provision
      fi
      exit 0 # test user missing, provision it
    '';
  };

  # Operator-facing reset. Deprovisioning destroys the existing home area
  # irrecoverably, so this always states what it is about to remove and asks
  # first; --force is provided for CI, which has no tty to answer on.
  testUserResetScript = pkgs.writeShellApplication {
    name = "ghaf-test-user-reset";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      # Not `[ a ] || [ b ] && force=true`: that parses as (a||b)&&c, which
      # yields a non-zero status when neither matches and would trip set -e.
      force=false
      case "''${1:-}" in
        --force | -f) force=true ;;
      esac

      if homectl inspect ${testUserName} > /dev/null 2>&1; then
        echo "'${testUserName}' already exists, nothing to do."
        exit 0
      fi

      echo "Existing home areas on this device:"
      homectl list
      echo ""
      echo "Provisioning '${testUserName}' requires removing every home area listed"
      echo "above. Their home images are deleted and CANNOT be recovered."
      echo ""

      if ! $force; then
        printf "Remove them and provision '${testUserName}'? [y/N] "
        read -r reply
        case "$reply" in
          [yY] | [yY][eE][sS]) ;;
          *)
            echo "Aborted, nothing was removed."
            exit 1
            ;;
        esac
      fi

      echo "Removing existing users..."
      systemctl start user-provision-remove.service

      echo "Provisioning '${testUserName}'..."
      systemctl start user-provision-test.service

      if homectl inspect ${testUserName} > /dev/null 2>&1; then
        echo "'${testUserName}' provisioned."
      else
        echo "Failed to provision '${testUserName}'." >&2
        exit 1
      fi
    '';
  };

in
{
  _file = ./user-provision.nix;

  options.ghaf.services.user-provisioning = {
    enable = mkEnableOption "Ghaf provisioning service";

    # AD setup toggle
    enableAD = mkOption {
      description = "Enable Active Directory join for provisioning.";
      type = types.bool;
      default = config.ghaf.users.adUsers.enable;
      readOnly = true;
    };
    # Homed user setup toggle
    enableHomed = mkOption {
      description = "Enable systemd-homed user setup for provisioning.";
      type = types.bool;
      default = config.ghaf.users.homedUser.enable;
      readOnly = true;
    };

    autoProvisionTestUser = mkOption {
      description = ''
        Provision the automated-test user at boot on debug images, instead of
        waiting for the test suite to start `user-provision-test.service`.

        Defaults to false, and deliberately so: the test unit stops
        `user-provision-interactive`, so enabling this on an image a developer
        installs means the interactive first-boot prompt never runs and they can
        never create their own account. Turn it on for CI and test-rig images,
        where a fresh flash should come up already testable.

        With this off, a freshly installed debug image is still testable -- the
        suite starts the unit on demand and it succeeds, because no test user
        exists yet. On a device that already has a login user, use
        `ghaf-test-user-reset` instead.
      '';
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.enableAD -> !cfg.enableHomed;
        message = "AD domain join and homed user setup modules cannot be combined at the moment.";
      }
    ];

    # Create persistent file for provisioning lock
    ghaf.storagevm.directories = lib.mkIf config.ghaf.storagevm.enable [ "/var/lib/ghaf" ];

    # Install JSON provisioning configuration
    environment.etc."ghaf/provisioning.json".source = provisioningConfig;

    # Add provisioning script to system packages
    environment.systemPackages = [
      pkgs.user-provision
    ]
    ++ optionals (config.ghaf.profiles.debug.enable && cfg.enableHomed) [ testUserResetScript ];

    systemd.services = {
      # Interactive provisioning service
      user-provision-interactive = {
        description = "Ghaf User Provisioning (interactive)";
        enable = true;
        requiredBy = [ "multi-user.target" ];
        before = [
          "greetd.service"
          "display-manager.service"
        ]
        ++ optionals cfg.enableAD [ "sssd.service" ];
        after = [
          "network-online.target"
        ]
        ++ optionals cfg.enableHomed [ "systemd-homed.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = true;
          TTYVHangup = true;
          PrivateTmp = true;
          ExecCondition = "${getExe execConditionScript}";
          ExecStartPre = optionalString config.ghaf.graphics.boot.enable "${pkgs.systemd}/bin/systemctl stop plymouth-start.service";
          ExecStart = "${getExe pkgs.user-provision}";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Non-interactive provisioning service for automated testing
      user-provision-test = mkIf (config.ghaf.profiles.debug.enable && cfg.enableHomed) {
        description = "Ghaf User Provisioning (testing)";
        enable = true;
        # Only pulled into the boot transaction when explicitly asked for; see
        # the autoProvisionTestUser option for why that is not the default.
        requiredBy = optionals cfg.autoProvisionTestUser [ "multi-user.target" ];
        before = optionals cfg.autoProvisionTestUser [
          "greetd.service"
          "display-manager.service"
        ];
        after = [ "systemd-homed.service" ];
        serviceConfig = {
          Type = "oneshot";
          PrivateTmp = true;
          # Asks "does the test user exist?", not "is the device provisioned?".
          ExecCondition = "${getExe testExecConditionScript}";
          ExecStart = "${getExe pkgs.user-provision} --non-interactive --username ${testUserName} --realname \"${testUserRealName}\" --password \"${testUserPassword}\"";
          ExecStartPost = [
            "${pkgs.systemd}/bin/systemctl stop user-provision-interactive"
          ];
        };
      };

      user-provision-remove = {
        description = "Ghaf User Provisioning (deprovisioning)";
        enable = true;
        after = [ "systemd-homed.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe deprovisioningScript}";
        };
      };
    };
  };
}
