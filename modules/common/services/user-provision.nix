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
      ${optionalString cfg.enableHomed ''
        SECONDS=0
        while ! user-provision --remove; do
          sleep 2
          if [ $SECONDS -ge 10 ]; then
            echo "Timeout reached after 10 seconds, proceeding anyway..."
            exit 1
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

      # Remove provisioning lock
      rm /var/lib/ghaf/user-provisioning.lock

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
        # No provisioning required
        exit 0
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
    environment.systemPackages = [ pkgs.user-provision ];

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
        after = [ "systemd-homed.service" ];
        serviceConfig = {
          Type = "oneshot";
          PrivateTmp = true;
          ExecCondition = "${getExe execConditionScript}";
          ExecStart = "${getExe pkgs.user-provision} --non-interactive --username testuser --realname \"Test User\" --password \"testpw\"";
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
