# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.orbit;

  givc-cli = "${lib.getExe' pkgs.givc-cli "givc-cli"} ${
    lib.replaceString "/run" "/etc" config.ghaf.givc.cliArgs
  }";

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

  ghafWipe = pkgs.writeShellApplication {
    name = "ghaf-wipe";
    runtimeInputs =
      with pkgs;
      [
        coreutils
        cryptsetup
        systemd
        util-linux
      ]
      ++ lib.optionals (
        config.ghaf.storage.encryption.enable && config.ghaf.storage.encryption.backendType == "tpm2"
      ) [ config.ghaf.security.tpm2.tools ];
    text = ''
      # Ignore stop signals for the duration of the wipe - once started
      # this must complete. A SIGKILL from root can still terminate us,
      # but that requires deliberate action and gives us a window to
      # finish the critical LUKS erase before poweroff.
      trap ''' TERM INT HUP QUIT PIPE

      echo "[1/3] Stopping virtual machines..."
      systemctl mask --runtime 'microvm@*.service' 2>/dev/null || true
      systemctl kill --kill-whom=all --signal=SIGKILL 'microvm@*.service' 2>/dev/null || true

      echo "      Done."

      echo "[2/3] Wiping..."
      ${lib.optionalString config.ghaf.storage.encryption.enable ''
        P_DEVPATH=$(readlink -f ${config.ghaf.storage.encryption.partitionDevice})

        if cryptsetup -q isLuks "$P_DEVPATH"; then
          echo "      Erasing all LUKS keyslots - data is unrecoverable beyond this point..."
          cryptsetup luksErase -q "$P_DEVPATH"
          ${lib.optionalString (config.ghaf.storage.encryption.backendType == "tpm2") ''
            echo "      Clearing TPM - sealed blobs in any header backup are now invalid..."
            tpm2_clear || true
          ''}
          echo "      Done."
          echo "[3/3] Powering off..."
          systemctl poweroff -ff
        fi
      ''}

      echo "      Not a LUKS device - overwriting persist with zeroes..."
      PERSIST_DEV=$(findmnt -n -o SOURCE /persist)
      # Discard first, so even if power is cut, at least the blocks are discarded
      blkdiscard -f "$PERSIST_DEV" 2>/dev/null || true
      shred -n 0 -z "$PERSIST_DEV" || true
      echo "      Done."

      echo "[3/3] Powering off..."
      systemctl poweroff -ff
    '';
  };

  ghafWipeRequest = pkgs.writeShellApplication {
    name = "ghaf-wipe-request";
    runtimeInputs = with pkgs; [
      givc-cli
      libnotify
      systemd
      gawk
    ];
    text = ''
      trap ''' TERM INT HUP QUIT PIPE
      # Terminate all active sessions immediately
      loginctl list-sessions --no-legend | awk '{print $1}' | xargs -r loginctl terminate-session || true
      # Trigger host-side wipe (host takes it from here)
      systemd-run --no-block \
        -p DefaultDependencies=no -p TimeoutSec=5 \
        -- ${givc-cli} start service --vm "ghaf-host" ${cfg.host.wipeService}.service
    '';
  };

  # Validation: require one of enrollSecret or enrollSecretPath
in
{
  _file = ./default.nix;

  options.ghaf.services.orbit = {
    enable = lib.mkEnableOption "Fleet Orbit systemd service";

    debug = lib.mkEnableOption "debug logging";

    gui.enable = lib.mkEnableOption "Fleet Orbit GUI tools and config";

    host = {
      enable = lib.mkEnableOption "Fleet Orbit config for the host";
      wipeService = lib.mkOption {
        type = lib.types.str;
        description = "Ghaf wipe service name";
        readOnly = true;
        default = "ghaf-wipe";
      };
    };

    # NOTE: We only expose the options for the flags from orbit that make sense
    # when you assume that update and fleet desktop are off. Other flags that
    # pertain to where things are stored are also hard-coded. See
    # https://github.com/fleetdm/fleet/blob/main/orbit/cmd/orbit/orbit.go
    # for the possible flags that could be exposed.

    desktopApp.enable = lib.mkEnableOption "Orbit fleet-desktop desktop app";

    devMode = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable development mode.";
    };

    enableScripts = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Enable script execution.";
    };

    endUserEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "End user email (experimental).";
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

    fleetDesktopAlternativeBrowserHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Alternative browser host for Fleet Desktop.";
    };

    fleetDesktopPackage = lib.mkPackageOption pkgs "fleet-desktop" { };

    fleetDesktopTLSClientCertificate = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to TLS client certificate for Fleet Desktop to authenticate to the Fleet server.";
    };

    fleetDesktopTLSClientKey = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to TLS client key for Fleet Desktop to authenticate to the Fleet server.";
    };

    fleetManagedHostIdentityCertificate = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Use TPM-backed key for Fleet EE (requires license).";
    };

    fleetUrl = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "https://";
      example = "https://your-fleet.example.com";
      description = "The base URL of the Fleet server.";
    };

    hostIdentifier = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Host identifier mode (e.g. 'uuid').";
    };

    hostnameFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the hostname to use instead of system hostname. Useful for dynamic hostname environments.";
    };

    insecure = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Disable TLS certificate verification.";
    };

    logDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/log/orbit";
      description = "Orbit log directory.";
    };

    orbitPackage = lib.mkPackageOption pkgs "fleet-orbit" { };

    osqueryPackage = lib.mkPackageOption pkgs "osquery" { };

    rootDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/orbit";
      description = "Orbit runtime directory (node key, osquery db, sockets). Set to a persistent path to avoid re-enrollment.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # GUI fleet MDM config
      (lib.mkIf cfg.gui.enable {
        assertions = [
          {
            assertion = lib.hasPrefix "https://" cfg.fleetUrl;
            message = "services.orbit.fleetUrl must start with https://.";
          }
        ];
        systemd = {
          services = {
            orbit = {
              description = "Orbit OSQuery";
              wantedBy = [ "multi-user.target" ];

              after = [
                "network.service"
                "syslog.service"
              ];

              unitConfig = lib.mkIf (cfg.hostnameFile != null || cfg.enrollSecretPath != null) {
                ConditionPathExists =
                  lib.optionals (cfg.hostnameFile != null) [ cfg.hostnameFile ]
                  ++ lib.optionals (cfg.enrollSecretPath != null) [ cfg.enrollSecretPath ];
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
            ghaf-wipe-request = {
              description = "Orbit Remote Wipe Request";

              after = [
                "network.service"
              ];

              serviceConfig = {
                ExecStart = lib.getExe ghafWipeRequest;
              };
            };
          };

          tmpfiles.rules = [
            "d ${cfg.rootDir} 0755 root root -"
            "d ${cfg.logDir} 0755 root root -"
          ];

          # This service replaces the built in orbit logic for detecting running
          # sessions and starting the fleet-desktop.
          user.services.fleet-desktop = {
            inherit (cfg.desktopApp) enable;
            description = "Fleet Desktop GUI";
            after = [
              "graphical-session.target"
              "orbit.service"
            ];
            wantedBy = [ "graphical-session.target" ];

            environment = lib.mkMerge [
              {
                FLEET_DESKTOP_DEVICE_IDENTIFIER_PATH = "${cfg.rootDir}/identifier";
                FLEET_DESKTOP_FLEET_URL = cfg.fleetUrl;
              }
              (lib.optionalAttrs (cfg.fleetDesktopAlternativeBrowserHost != null) {
                FLEET_DESKTOP_ALTERNATIVE_BROWSER_HOST = cfg.fleetDesktopAlternativeBrowserHost;
              })
              (lib.optionalAttrs (cfg.fleetDesktopTLSClientCertificate != null) {
                FLEET_DESKTOP_FLEET_TLS_CLIENT_CERTIFICATE = cfg.fleetDesktopTLSClientCertificate;
              })
              (lib.optionalAttrs (cfg.fleetDesktopTLSClientKey != null) {
                FLEET_DESKTOP_FLEET_TLS_CLIENT_KEY = cfg.fleetDesktopTLSClientKey;
              })
            ];

            serviceConfig = {
              ExecStart = lib.getExe' cfg.fleetDesktopPackage "fleet-desktop";
              Restart = "on-failure";
              RestartSec = 10;
            };
          };
        };

        environment.systemPackages = [ pkgs.xdg-utils ] ++ lib.optionals cfg.debug [ pkgs.fleetctl ];

        environment.sessionVariables = {
          PATH = lib.mkAfter "$PATH:${pkgs.xdg-utils}/bin";
        };
      })

      # Host fleet MDM config
      (lib.mkIf cfg.host.enable {
        systemd.services."${cfg.host.wipeService}" = {
          description = "Ghaf Wipe";

          unitConfig = {
            DefaultDependencies = false;
          };

          serviceConfig = {
            Type = "oneshot";
            Restart = "no";

            StandardOutput = "journal";
            StandardError = "journal";

            ExecStart = lib.getExe ghafWipe;
          };
        };
      })
    ]
  );
}
