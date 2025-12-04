# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.provisioning;
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
      system_setup = {
        enable_ad_config = cfg.enableAd;
        enable_fleet_enrollment = cfg.enableFleetEnrollment;
      };

      # Reference existing SSSD configuration when AD join is enabled
      ad_config = optionalAttrs (cfg.enableAd && config.ghaf.services.sssd.enable) (
        let
          # Get first domain from SSSD config
          firstDomainName = lib.head (lib.attrNames config.ghaf.services.sssd.domains);
          firstDomain = config.ghaf.services.sssd.domains.${firstDomainName} or { };
        in
        {
          # Currently, the script only supports a single domain
          # via config.
          domain = firstDomain.ad.domain or "";
          realm = firstDomain.krb5.realm or "";
          ad_server = lib.head firstDomain.ad.controllers or "";
          # Currently, the script does not support pre-fixes like ldap:// or ldaps://
          ldap_server = lib.removePrefix "ldaps://" (
            lib.removePrefix "ldap://" (lib.head firstDomain.ldap.uri)
          );
        }
      );

      # User setup configuration with sensible defaults
      user_config = optionalAttrs cfg.enableHomed {
        home_size = config.ghaf.users.homedUser.homeSize;
        inherit (config.ghaf.users.homedUser) uid;
        fs_type = "ext4";
        shell = "/run/current-system/sw/bin/bash";
        groups = "users${
          optionalString (
            config.ghaf.users.homedUser.extraGroups != [ ]
          ) ",${lib.concatStringsSep "," config.ghaf.users.homedUser.extraGroups}"
        }";
        fido_auth = config.ghaf.users.homedUser.fidoAuth;
      };

      # Storage configuration (if storagevm is available)
      storage = optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
        mount_path = config.ghaf.storagevm.mountPath;
      };
    }
  );

  # Determine provisioning mode
  provisioning_mode = if cfg.enableAd then if cfg.enableHomed then "full" else "system" else "user";

in
{
  options.ghaf.services.provisioning = {
    enable = mkEnableOption "Ghaf provisioning service";

    # System setup toggle
    enableAd = mkOption {
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
    # Future: Fleet management enrollment toggle
    enableFleetEnrollment = mkEnableOption "Fleet management enrollment during provisioning";
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.enableAd || cfg.enableHomed;
        message = "At least one of 'enableAd' or 'enableHomed' must be enabled for provisioning.";
      }
      {
        assertion = cfg.enableAd -> !cfg.enableHomed;
        message = "AD and homed user setup modules cannot be combined at the moment.";
      }
    ];

    # Install JSON provisioning configuration
    environment.etc."ghaf/provisioning.json".source = provisioningConfig;

    # Add provisioning script to system packages
    environment.systemPackages = [ pkgs.ghaf-provision ];

    systemd.services = {
      # Interactive provisioning service
      ghaf-provision-interactive = {
        description = "Ghaf Provisioning (interactive)";
        enable = true;
        requiredBy = [ "multi-user.target" ];
        before = [
          "greetd.service"
          "display-manager.service"
        ]
        ++ optionals cfg.enableAd [ "sssd.service" ];
        after = [
          "network-online.target"
        ]
        ++ optionals cfg.enableHomed [ "systemd-homed.service" ];
        wants = [ "network-online.target" ];

        unitConfig.ConditionPathExists = "!/var/lib/nixos/provisioning.lock";
        serviceConfig = {
          Type = "oneshot";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = true;
          TTYVHangup = true;
          PrivateTmp = true;
          ExecStartPre = optionalString config.ghaf.graphics.boot.enable "${pkgs.systemd}/bin/systemctl stop plymouth-start.service";
          ExecStart = "${getExe pkgs.ghaf-provision} ${provisioning_mode}";
          ExecStartPost = "${pkgs.coreutils}/bin/install -m 000 /dev/null /var/lib/nixos/provisioning.lock";
          Restart = "on-failure";
          RestartSec = "5s";
        };
      };

      # Non-interactive provisioning service for automated testing
      ghaf-provision-test = mkIf (config.ghaf.profiles.debug.enable && cfg.enableHomed) {
        description = "Ghaf Automated Test Provisioning";
        enable = true;
        after = [ "systemd-homed.service" ];

        unitConfig.ConditionPathExists = "!/var/lib/nixos/provisioning.lock";
        serviceConfig = {
          Type = "oneshot";
          PrivateTmp = true;
          ExecStart = "${getExe pkgs.ghaf-provision} user --non-interactive --username testuser --realname \"Test User\" --password \"testpw\"";
          ExecStartPost = [
            "${pkgs.systemd}/bin/systemctl stop ghaf-provision-interactive"
            "${pkgs.coreutils}/bin/install -m 000 /dev/null /var/lib/nixos/provisioning.lock"
          ];
        };
      };
    };
  };
}
