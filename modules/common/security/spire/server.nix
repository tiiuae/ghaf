# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spire.server;
  inherit (lib)
    filterAttrs
    getExe
    mkIf
    mkOption
    mkEnableOption
    types
    optionalString
    concatMapStringsSep
    ;
  runtimeDataDir = "/run/spire/server";
  tokenDir = "/etc/common/spire/tokens";
  socketPath = "${runtimeDataDir}/public/api.sock";
  dataDir = "/var/lib/spire/server";
  spire-package = config.ghaf.common.spire.package;
  spireAgents = config.ghaf.common.spire.agents;
  inherit (config.ghaf.common.spire.server) healthCheckPort;
  inherit (config.ghaf.common.spire.server) trustDomain;
  spireAgentVMs = builtins.attrNames spireAgents;
  getVMsByAttestation =
    mode: builtins.attrNames (filterAttrs (_vm: cfg: (cfg.nodeAttestationMode == mode)) spireAgents);

  joinTokenVMs = getVMsByAttestation "join_token";
  joinTokenPlugin = optionalString (builtins.length joinTokenVMs > 0) ''
    NodeAttestor "join_token" {
      plugin_data {}
    }
  '';

  serverConf = ''
    server {
      bind_address = "${config.ghaf.common.spire.server.address}"
      bind_port = ${toString config.ghaf.common.spire.server.port}
      trust_domain = "${trustDomain}"
      data_dir = "${dataDir}"
      log_level = "${cfg.logLevel}"
      socket_path = "${socketPath}"
    }
    health_checks {
      listener_enabled = true
      bind_address = "${config.ghaf.common.spire.server.address}"
      bind_port = "${toString healthCheckPort}"
      live_path = "/live"
      ready_path = "/ready"
    }
    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "sqlite3"
          connection_string = "${dataDir}/datastore.sqlite3"
        }
      }
      KeyManager "disk" {
        plugin_data {
          keys_path = "${dataDir}/keys.json"
        }
      }
      ${joinTokenPlugin}
    }
  '';

  spireGenerateJoinTokensApp = pkgs.writeShellApplication {
    name = "spire-generate-join-tokens";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      spire-package
    ];
    text = ''
      mkdir -p "${tokenDir}"
      chmod 755 "${tokenDir}"

      # Wait until the server is up
      for i in $(seq 1 60); do
        if spire-server healthcheck -socketPath ${socketPath} >/dev/null 2>&1; then
          echo "SPIRE server is ready"
          break
        fi
        echo "Waiting for SPIRE server... ($i/60)"
        sleep 1
      done

      ${concatMapStringsSep "\n" (vm: ''
        tokenFile="${tokenDir}/${vm}.token"

        # Check if agent is already registered
        if spire-server agent list -socketPath ${socketPath} 2>/dev/null | grep -q "spiffe://${trustDomain}/agent/${vm}"; then
          echo "Agent ${vm} already registered, skipping token generation"
        else
          echo "Generating new token for ${vm}"
          # Capture output and check success in one go
          if ! output=$(spire-server token generate -socketPath "${socketPath}" -spiffeID "spiffe://${trustDomain}/${vm}"); then
              echo "Error: SPIRE token generation failed!" >&2
              exit 1
          fi

          token=$(echo "$output" | awk '/^Token:/ {print $2}')

          printf '%s\n' "$token" > "$tokenFile"
          chmod 0644 "$tokenFile"
          echo "Token written to $tokenFile"
        fi
      '') joinTokenVMs}
    '';
  };

  spirePublishBundleApp = pkgs.writeShellApplication {
    name = "spire-publish-bundle";
    runtimeInputs = [
      pkgs.coreutils
      spire-package
    ];
    text = ''
      out="${cfg.trustBundlePath}"
      mkdir -p "$(dirname "$out")"

      # Wait until the server API socket exists and the server is ready
      for _ in $(seq 1 60); do
        if [ -S "${socketPath}" ] && spire-server healthcheck -socketPath "${socketPath}" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      if [ ! -S "${socketPath}" ]; then
        echo "ERROR: SPIRE server socket not found at ${socketPath}" >&2
        exit 1
      fi

      tmp="$(mktemp)"
      spire-server bundle show -socketPath "${socketPath}" > "$tmp"
      if [ ! -s "$tmp" ]; then
        echo "ERROR: bundle export produced empty output" >&2
        exit 1
      fi

      install -m 0644 -o root -g root "$tmp" "$out"
      rm -f "$tmp"
      echo "Wrote $out"
    '';
  };

  spireCreateWorkloadEntriesApp = import ./create-workload-entries.nix {
    inherit
      pkgs
      lib
      config
      spire-package
      socketPath
      spireAgentVMs
      ;
  };
in
{
  _file = ./server.nix;

  options.ghaf.security.spire.server = {
    enable = mkEnableOption "SPIRE server";

    logLevel = mkOption {
      type = types.str;
      default = "INFO";
      description = "SPIRE server log level";
    };

    trustBundlePath = mkOption {
      type = types.path;
      default = "/etc/common/spire/bundle.pem";
      description = "Path to the SPIRE trust bundle PEM file (used to verify the server during bootstrap)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ spire-package ];
    environment.etc."spire/server.conf".text = serverConf;
    services.spire.server = {
      enable = true;
      package = spire-package;
      configFile = "/etc/spire/server.conf";

    };

    systemd = {
      tmpfiles.rules = [
        "d /run/spire 0755 root root - -"
        "d ${runtimeDataDir} 0755 root root - -"
        "d ${runtimeDataDir}/public 0755 root root - -"
        "d ${runtimeDataDir}/private 0755 root root - -"
        "d ${tokenDir} 0755 root root - -"
      ];

      services = {
        spire-server = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [
              "${dataDir}"
              "${runtimeDataDir}"
            ];
          };
        };
        spire-generate-join-tokens = mkIf (builtins.length joinTokenVMs > 0) {
          description = "Generate SPIRE join tokens for Ghaf VMs (PoC)";
          wantedBy = [ "multi-user.target" ];
          after = [
            "spire-server.service"
            "network-online.target"
          ];
          wants = [
            "spire-server.service"
            "network-online.target"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = getExe spireGenerateJoinTokensApp;
          };
        };
        spire-publish-bundle = {
          description = "Publish SPIRE trust bundle (PoC)";
          wantedBy = [ "multi-user.target" ];
          after = [ "spire-server.service" ];
          wants = [ "spire-server.service" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe spirePublishBundleApp;
          };
        };
        spire-create-workload-entries = {
          description = "Create SPIRE workload entries";
          wantedBy = [ "multi-user.target" ];
          after = [
            "spire-server.service"
            "spire-generate-join-tokens.service"
          ];
          wants = [ "spire-server.service" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = getExe spireCreateWorkloadEntriesApp;
          };
        };
      };
    };
    networking.firewall.allowedTCPPorts = [
      config.ghaf.common.spire.server.port
      config.ghaf.common.spire.server.healthCheckPort
    ];
  };
}
