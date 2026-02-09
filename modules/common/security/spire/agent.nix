# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spire.agent;
  dataDir = "/var/lib/spire/agent";
  runtimeDataDir = "/run/spire/agent";
  inherit (lib)
    getExe
    mkIf
    mkOption
    mkEnableOption
    optionalString
    types
    ;
  spire-package = config.ghaf.common.spire.package;
  healthCheckPort = toString config.ghaf.common.spire.server.healthCheckPort;

  joinTokenConf = optionalString (cfg.nodeAttestationMode == "join_token") ''
    join_token_file = "${cfg.settings.join_token.token}"
  '';
  joinTokenPlugin = optionalString (cfg.nodeAttestationMode == "join_token") ''
    NodeAttestor "join_token" {
      plugin_data {}
    }
  '';
  agentConf = ''
    agent {
      data_dir = "${dataDir}"
      log_level = "${cfg.logLevel}"
      server_address = "${config.ghaf.common.spire.server.address}"
      server_port = ${toString config.ghaf.common.spire.server.port}
      trust_domain = "${config.ghaf.common.spire.server.trustDomain}"
      trust_bundle_path = "${cfg.trustBundlePath}"
      socket_path = "${runtimeDataDir}/agent.sock"
      ${joinTokenConf}
    }

    plugins {
      ${joinTokenPlugin}

      WorkloadAttestor "unix" {
        plugin_data {}
      }
      KeyManager "disk" {
        plugin_data {
          directory = "${dataDir}/keys"
        }
      }
    }
  '';

  server-health = pkgs.writeShellApplication {
    name = "spire-server-healthcheck";

    runtimeInputs = [
      pkgs.curl
    ];

    text = ''
      SERVER_URL="http://${config.ghaf.common.spire.server.address}:${healthCheckPort}/ready"
      MODE="${cfg.nodeAttestationMode}"

      echo "Checking SPIRE Server readiness at $SERVER_URL..."

      until curl --fail --silent "$SERVER_URL" > /dev/null 2>&1; do
        echo "SPIRE Server is not ready yet. Retrying in 3 seconds..."
        sleep 3
      done

      if [ "$MODE" == "join_token" ]; then
        while [ ! -e "${cfg.settings.join_token.token}" ]; do
          echo "Waiting for server token..."
          sleep 1
        done
      fi
      echo "SPIRE Server is ready! Starting SPIRE Agent..."
    '';
  };
in
{
  _file = ./agent.nix;

  options.ghaf.security.spire.agent = {
    enable = mkEnableOption "SPIRE agent";
    nodeAttestationMode = mkOption {
      type = types.spireNodeAttestationMode;
      default = "join_token";
      description = "Node attestation mode";
    };
    workloads = mkOption {
      type = types.spireWorkloads;
      default = [ ];
      description = "List of workloads for this spire agent";
    };
    trustBundlePath = mkOption {
      type = types.path;
      default = "/etc/common/spire/bundle.pem";
      description = "Path to the SPIRE trust bundle PEM file (used to verify the server during bootstrap)";
    };
    logLevel = mkOption {
      type = types.str;
      default = "INFO";
      description = "SPIRE server log level";
    };
    settings = {
      join_token = {
        token = mkOption {
          type = types.path;
          default = "/etc/common/spire/tokens/${config.networking.hostName}.token";
          description = "SPIRE server log level";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc."spire/agent.conf".text = agentConf;
    services.spire.agent = {
      enable = true;
      package = spire-package;
      configFile = "/etc/spire/agent.conf";
    };

    environment.systemPackages = [ spire-package ];
    systemd = {
      services = {
        spire-agent = {
          requires = [ "network-online.target" ];
          after = [
            "network-online.target"
          ];

          unitConfig = {
            RequiresMountsFor = [ "/etc/common" ];
          };

          serviceConfig = {
            ExecStartPre = getExe server-health;
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              "${dataDir}"
              "${runtimeDataDir}"
            ];
          };
        };
      };
      tmpfiles.rules = [
        "d /run/spire 0755 root root - -"
        "d ${runtimeDataDir} 2750 spire-agent spire-agent - -"
      ];
    };
  };
}
