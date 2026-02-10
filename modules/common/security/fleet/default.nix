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

  nullOrBoolToString = v: if v == null then null else lib.boolToString v;

  orbitSpecifiedPreStart = pkgs.writeShellApplication {
    name = "orbit-specified-prestart";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      uuid_file="/etc/common/ghaf/uuid"
      flagfile="${cfg.rootDir}/osquery.flags"
      if [ -r "$uuid_file" ]; then
        uuid="$(tr -d '\n' < "$uuid_file")"
        if [ -n "$uuid" ]; then
          mkdir -p "${cfg.rootDir}"
          printf -- "--specified_identifier=%s\n" "$uuid" > "$flagfile"
        else
          echo "orbit: uuid file empty: $uuid_file" >&2
        fi
      else
        echo "orbit: uuid file not readable: $uuid_file" >&2
      fi
    '';
  };

  # Validation: require one of enrollSecret or enrollSecretPath
in
{
  _file = ./default.nix;

  options.services.orbit = {
    enable = lib.mkEnableOption "Fleet Orbit systemd service";

    orbitPackage = lib.mkPackageOption pkgs "fleet-orbit" { };

    osqueryPackage = lib.mkPackageOption pkgs "osquery" { };

    fleetDesktopPackage = lib.mkPackageOption pkgs "fleet-desktop" { };

    # NOTE: We only expose the options for the flags from orbit that make sense
    # when you assume that update and fleet desktop are off. Other flags that
    # pertain to where things are stored are also hard-coded. See
    # https://github.com/fleetdm/fleet/blob/main/orbit/cmd/orbit/orbit.go
    # for the possible flags that could be exposed.

    fleetUrl = lib.mkOption {
      type = lib.types.nonEmptyStr;
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

    rootDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/orbit";
      description = "Orbit runtime directory (node key, osquery db, sockets). Set to a persistent path to avoid re-enrollment.";
    };

    logDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/orbit";
      description = "Orbit log directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.fleetUrl;
        message = "services.orbit.fleetUrl must start with https://.";
      }
    ];

    systemd = {
      services.orbit = {
        description = "Orbit OSQuery";
        wantedBy = [ "multi-user.target" ];

        after = [
          "network.service"
          "syslog.service"
        ];

        unitConfig = lib.mkIf (cfg.hostnameFile != null) {
          ConditionPathExists = cfg.hostnameFile;
        };

        environment = lib.mkMerge [
          {
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
            ORBIT_INSECURE = nullOrBoolToString cfg.insecure;

            # Hardcoded variables to ensure we play nice with nix.
            ORBIT_DISABLE_KEYSTORE = "true";
            ORBIT_DISABLE_UPDATES = "true";
            ORBIT_FLEET_DESKTOP = "false";
            ORBIT_LOG_FILE = "${cfg.logDir}/orbit.log";
            ORBIT_OSQUERY_DB = "${cfg.rootDir}/osquery.db";
            ORBIT_ROOT_DIR = cfg.rootDir;
            NIX_ORBIT_OSQUERYD_PATH = "${cfg.osqueryPackage}/bin/osqueryd";
            NIX_ORBIT_OSQUERY_LOG_PATH = "${cfg.logDir}/osquery/";
          }
          (lib.optionalAttrs (cfg.hostnameFile != null) {
            ORBIT_HOSTNAME_FILE = cfg.hostnameFile;
            OSQUERY_HOSTNAME_FILE = cfg.hostnameFile;
            OSQUERY_UUID_FILE = "/etc/common/ghaf/uuid";
          })
          (lib.optionalAttrs (cfg.hostIdentifier != null) {
            ORBIT_HOST_IDENTIFIER = cfg.hostIdentifier;
          })
        ];

        preStart = lib.mkIf (cfg.hostIdentifier == "specified") (lib.getExe orbitSpecifiedPreStart);

        serviceConfig = {
          ExecStart = lib.getExe cfg.orbitPackage;
          TimeoutStartSec = 0;
          Restart = "always";
          RestartSec = 60;
        };
      };

      tmpfiles.rules = [
        "d ${cfg.rootDir} 0755 root root -"
        "d ${cfg.logDir} 0755 root root -"
      ];

      # This service replaces the built in orbit logic for detecting running
      # sessions and starting the fleet-desktop.
      user.services."fleet-desktop" = {
        description = "Fleet Desktop GUI";
        after = [
          "graphical-session.target"
          "orbit.service"
        ];
        wantedBy = [ "graphical-session.target" ];

        environment = {
          FLEET_DESKTOP_DEVICE_IDENTIFIER_PATH = "${cfg.rootDir}/identifier";
          FLEET_DESKTOP_FLEET_URL = cfg.fleetUrl;
        };

        serviceConfig = {
          ExecStart = "${cfg.fleetDesktopPackage}/bin/fleet-desktop";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
    };

    environment.systemPackages = [ pkgs.xdg-utils ];

    environment.sessionVariables = {
      PATH = lib.mkAfter "$PATH:${pkgs.xdg-utils}/bin";
    };
  };
}
