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

      if [ ! -S "${socketPath}" ] \
        || ! spire-server healthcheck -socketPath "${socketPath}" >/dev/null 2>&1; then
        echo "ERROR: SPIRE server is not ready at ${socketPath}" >&2
        exit 1
      fi

      tmp="$(mktemp "$out.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      spire-server bundle show -socketPath "${socketPath}" > "$tmp"
      if [ ! -s "$tmp" ]; then
        echo "ERROR: bundle export produced empty output" >&2
        exit 1
      fi

      chmod 0644 "$tmp"
      mv -f "$tmp" "$out"
      echo "Wrote $out"
    '';
  };

  spireRefreshIdentityApp = pkgs.writeShellApplication {
    name = "spire-refresh-identity";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.systemd
      spire-package
    ];
    text = ''
      # The boot barrier can time out before NTP synchronises on a later clock change.
      sync_state="$(cat /run/ghaf-clock-synced 2>/dev/null || echo missing)"
      if [ "$sync_state" != "synchronised" ] \
        && [ "$(timedatectl show -p NTPSynchronized --value)" != "yes" ]; then
        echo "spire-refresh-identity: clock barrier reports '$sync_state' and NTP is not synchronised;" \
             "leaving identities unchanged." >&2
        exit 0
      fi

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT
      timeout 5 openssl s_client -connect ${
        escapeShellArg (
          (
            if hasInfix ":" config.ghaf.common.spire.server.address then
              "[${config.ghaf.common.spire.server.address}]"
            else
              config.ghaf.common.spire.server.address
          )
          + ":${toString config.ghaf.common.spire.server.port}"
        )
      } -alpn h2 -showcerts </dev/null > "$tmp/chain.pem"
      openssl x509 -in "$tmp/chain.pem" -out "$tmp/svid.pem"
      spire-server bundle show -socketPath "${socketPath}" > "$tmp/bundle.pem"

      if ! openssl verify -CAfile "$tmp/bundle.pem" -untrusted "$tmp/chain.pem" "$tmp/svid.pem"; then
        # SPIRE's taint check also validates time, so it cannot rotate a future-dated SVID.
        echo "spire-refresh-identity: server certificate chain is invalid; restarting SPIRE."
        systemctl restart spire-server.service
      else
        echo "spire-refresh-identity: server certificate chain is valid; no restart needed."
      fi

      ${getExe spirePublishBundleApp}
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
            unitConfig.RequiresMountsFor = [ cfg.trustBundlePath ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${setupScript}";
              RemainAfterExit = true;
            };
          };
        spire-server = {
          requires = [
            "network.target"
            "local-fs.target"
            "spire-server-setup.service"
          ];
          after = [
            "network.target"
            "local-fs.target"
            "spire-server-setup.service"
          ];

          serviceConfig = {
            RuntimeDirectory = mkForce "spire-server";
            RuntimeDirectoryPreserve = "restart";
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
          wantedBy = [
            "multi-user.target"
            "spire-server.service"
          ];
          after = [ "spire-server.service" ];
          wants = [ "spire-server.service" ];
          unitConfig.RequiresMountsFor = [ cfg.trustBundlePath ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe spirePublishBundleApp;
            # Retry failures and refresh hourly so the file follows CA rotation.
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };
        spire-refresh-identity-after-time-sync = {
          description = "Refresh SPIRE identities after time synchronisation";
          wantedBy = [ "ghaf-clock-synced.target" ];
          wants = [ "spire-server.service" ];
          after = [
            "ghaf-wait-time-sync.service"
            "spire-server.service"
          ];
          unitConfig = {
            RequiresMountsFor = [ cfg.trustBundlePath ];
            # Successful checks reset this limit, leaving consecutive failures bounded.
            StartLimitIntervalSec = 300;
            StartLimitBurst = 5;
          };

          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe spireRefreshIdentityApp;
            ExecStartPost = "${pkgs.systemd}/bin/systemctl reset-failed spire-refresh-identity-after-time-sync.service";
            Restart = "on-failure";
            RestartSec = "5s";
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

      timers.spire-publish-bundle = {
        description = "Re-publish the SPIRE trust bundle so it tracks CA rotation";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "1h";
          AccuracySec = "1m";
          Unit = "spire-publish-bundle.service";
        };
      };
      timers.spire-refresh-identity-after-time-sync = {
        description = "Check SPIRE identities after clock changes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnClockChange = true;
          Unit = "spire-refresh-identity-after-time-sync.service";
        };
      };
    };
    networking.firewall.allowedTCPPorts = [
      config.ghaf.common.spire.server.port
      config.ghaf.common.spire.server.healthCheckPort
    ];
  };
}
