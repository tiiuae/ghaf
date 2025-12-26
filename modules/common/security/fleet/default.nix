# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.orbit;

  fleetPkgs = pkgs.callPackage ./pkgs.nix { };

  nullOrBoolToString = v: if v == null then null else lib.boolToString v;

  # Validation: require one of enrollSecret or enrollSecretPath
in
{
  options.services.orbit = {
    enable = lib.mkEnableOption "Fleet Orbit systemd service";

    orbitPackage = lib.mkPackageOption fleetPkgs "orbit" { };

    osqueryPackage = lib.mkPackageOption pkgs "osquery" { };

    fleetDesktopPackage = lib.mkPackageOption fleetPkgs "fleet-desktop" { };

    # NOTE: We only expose the options for the flags from orbit that make sense
    # when you assume that update and fleet desktop are off. Other flags that
    # pertain to where things are stored are also hard-coded. See
    # https://github.com/fleetdm/fleet/blob/main/orbit/cmd/orbit/orbit.go
    # for the possible flags that could be exposed.

    fleetUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://your-fleet.example.com";
      description = "The base URL of the Fleet server.";
    };

    enrollSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The enroll secret for authenticating to Fleet server. One of enrollSecret or enrollSecretPath must be set.";
    };

    enrollSecretPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the enroll secret file, this should be used with e.g. sops-nix if you want to keep the secret outside of your nix-store. One of enrollSecret or enrollSecretPath must be set.";
    };

    fleetCertificate = lib.mkOption {
      type = lib.types.path;
      default = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      description = "Path to the Fleet server certificate chain. Defaults to system CA bundle.";
    };

    debug = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable debug logging.";
    };

    devMode = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable development mode.";
    };

    hostIdentifier = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Host identifier mode (e.g. 'uuid').";
    };

    enableScripts = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable script execution.";
    };

    fleetDesktopAlternativeBrowserHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Alternative browser host for Fleet Desktop.";
    };

    fleetManagedHostIdentityCertificate = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Use TPM-backed key for Fleet EE (requires license).";
    };

    endUserEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "End user email (experimental).";
    };

    insecure = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Disable TLS certificate verification.";
    };

    hostnameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the hostname to use instead of system hostname. Useful for dynamic hostname environments.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.orbit = {
      description = "Orbit OSQuery";
      wantedBy = [ "multi-user.target" ];

      after = [
        "network.service"
        "syslog.service"
      ];

      unitConfig = lib.mkIf (cfg.hostnameFile != null) {
        ConditionPathExists = cfg.hostnameFile;
      };

      environment = {
        # Required config:
        ORBIT_FLEET_URL = cfg.fleetUrl;
        ORBIT_ENROLL_SECRET = cfg.enrollSecret;
        ORBIT_ENROLL_SECRET_PATH = cfg.enrollSecretPath;

        # Optional config:
        ORBIT_DEBUG = nullOrBoolToString cfg.debug;
        ORBIT_DEV_MODE = nullOrBoolToString cfg.devMode;
        ORBIT_ENABLE_SCRIPTS = nullOrBoolToString cfg.enableScripts;
        ORBIT_END_USER_EMAIL = cfg.endUserEmail;
        ORBIT_FLEET_CERTIFICATE = cfg.fleetCertificate;
        ORBIT_FLEET_DESKTOP_ALTERNATIVE_BROWSER_HOST = cfg.fleetDesktopAlternativeBrowserHost;
        ORBIT_FLEET_MANAGED_HOST_IDENTITY_CERTIFICATE = nullOrBoolToString cfg.fleetManagedHostIdentityCertificate;
        ORBIT_HOST_IDENTIFIER = cfg.hostIdentifier;
        ORBIT_HOSTNAME_FILE = cfg.hostnameFile;
        ORBIT_INSECURE = nullOrBoolToString cfg.insecure;

        # Hardcoded variables to ensure we play nice with nix.
        ORBIT_DISABLE_KEYSTORE = "true";
        ORBIT_DISABLE_UPDATES = "true";
        ORBIT_FLEET_DESKTOP = "false";
        ORBIT_LOG_FILE = "/var/log/orbit/orbit.log";
        ORBIT_OSQUERY_DB = "/var/lib/orbit/osquery.db";
        ORBIT_ROOT_DIR = "/var/lib/orbit";
        NIX_ORBIT_OSQUERYD_PATH = "${cfg.osqueryPackage}/bin/osqueryd";
        NIX_ORBIT_OSQUERY_LOG_PATH = "/var/log/orbit/osquery/";
        NIX_ORBIT_WRITE_FLEET_DESKTOP_IDENTIFIER = "true";
      };

      serviceConfig = {
        ExecStart = "${cfg.orbitPackage}/bin/orbit";
        TimeoutStartSec = 0;
        Restart = "always";
        RestartSec = 60;
        KillMode = "control-group";
        KillSignal = "SIGTERM";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/orbit 0755 root root -"
      "d /var/log/orbit 0755 root root -"
    ];

    # This service replaces the built in orbit logic for detecting running
    # sessions and starting the fleet-desktop.
    systemd.user.services."fleet-desktop" = {
      description = "Fleet Desktop GUI";
      after = [
        "graphical-session.target"
        "orbit.service"
      ];
      wantedBy = [ "graphical-session.target" ];

      environment = {
        FLEET_DESKTOP_DEVICE_IDENTIFIER_PATH = "/var/lib/orbit/identifier";
        FLEET_DESKTOP_FLEET_URL = cfg.fleetUrl;

        # NOTE: We override the serviceConfig.Environment path to ensure we
        # have xdg-utils, and all the user paths, otherwise opening the browser
        # can fail on some systems (depending on the default they've set).
        PATH = lib.mkForce "${pkgs.xdg-utils}/bin:/home/%u/.local/bin:/home/%u/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin:/usr/bin:/bin";
      };

      serviceConfig = {
        ExecStart = "${cfg.fleetDesktopPackage}/bin/fleet-desktop";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
