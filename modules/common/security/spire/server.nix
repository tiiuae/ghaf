# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.ghaf.security.spire.server;
  runtimeDataDir = "/run/spire-server";
  credSourceDir = "/etc/givc";
  socketPath = "${runtimeDataDir}/api.sock";
  dataDir = "${runtimeDataDir}";

  spire-package = config.ghaf.common.spire.package;
  spireAgents = config.ghaf.common.spire.agents;
  inherit (config.ghaf.common.spire.server) healthCheckPort;
  inherit (config.ghaf.common.spire.server) trustDomain;
  spireAgentVMs = builtins.attrNames spireAgents;
  upstreamAgent = config.ghaf.security.spire.agents.upstream or { enable = false; };
  upstreamAgentServiceName = "spire-agent-upstream";
  getVMsByAttestation =
    mode: builtins.attrNames (filterAttrs (_vm: cfg: (cfg.nodeAttestationMode == mode)) spireAgents);

  x509popVMs = getVMsByAttestation "x509pop";

  x509popPlugin = optionalString (builtins.length x509popVMs > 0) ''
    NodeAttestor "x509pop" {
      plugin_data {
        ca_bundle_path = "$CREDENTIALS_DIRECTORY/ca-cert.pem"
      }
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
      KeyManager "memory" {
        plugin_data {}
      }
      ${x509popPlugin}
    }
  '';

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

  spireServerUpstreamWorkloadApp = pkgs.writeShellApplication {
    name = "spire-server-upstream-workload";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      socket=${escapeShellArg upstreamAgent.socketPath}
      retry_interval=30

      probe_upstream_svid() {
        echo "Waiting to verify upstream SPIRE workload SVID issuance"

        while true; do
          # This is a one-shot probe for the initial upstream agent integration.
          # SVID persistence and renewal await the final backend requirements.
          if [ -S "$socket" ] && ${getExe' spire-package "spire-agent"} api fetch x509 \
            -silent \
            -socketPath "$socket" \
            -timeout 5s >/dev/null 2>&1; then
            echo "Fetched upstream SPIRE workload SVID for spire-server.service"
            return 0
          fi

          sleep "$retry_interval"
        done
      }

      # Keep retries asynchronous so the optional upstream path cannot delay
      # the independent local SPIRE server.
      probe_upstream_svid &
    '';
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
        "d ${runtimeDataDir} 0755 root root - -"
      ];

      services = {
        spire-server-setup =
          let
            setupScript = pkgs.writeShellScript "spire-agent-setup" ''
              ${pkgs.coreutils}/bin/rm -f ${cfg.trustBundlePath}
            '';
          in
          {
            description = "SPIRE server setup";
            wantedBy = [ "spire-server.service" ];
            before = [ "spire-server.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${setupScript}";
              RemainAfterExit = true;
            };
          };
        spire-server = {
          requires = [
            "network-online.target"
            "local-fs.target"
            "spire-server-setup.service"
          ];
          after = [
            "network-online.target"
            "local-fs.target"
            "spire-server-setup.service"
          ];

          serviceConfig = {
            RuntimeDirectory = mkForce "spire-server";
            StateDirectory = mkForce "spire-server";
            ReadWritePaths = [
              "${dataDir}"
              "${runtimeDataDir}"
            ];
          }
          // optionalAttrs upstreamAgent.enable {
            ExecStartPost = getExe spireServerUpstreamWorkloadApp;
            SupplementaryGroups = [ upstreamAgentServiceName ];
          }
          // optionalAttrs (builtins.length x509popVMs > 0) {
            LoadCredential = [
              "ca-cert.pem:${credSourceDir}/ca-cert.pem"
            ];
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
          after = [ "spire-server.service" ];
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
