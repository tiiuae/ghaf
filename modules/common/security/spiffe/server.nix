# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# SPIRE Server Module
#
# Runs the SPIRE server (identity authority) on admin-vm.
# Supports dual attestation: join_token for app VMs + tpm_devid for system VMs.
# Server address is derived from hostConfig (not hardcoded).
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.server;

  tpmAttestationEnabled = cfg.tpmAttestation.enable;

  # Generate server.conf HCL
  serverConf = ''
    server {
      bind_address = "${cfg.bindAddress}"
      bind_port = ${toString cfg.bindPort}
      trust_domain = "${cfg.trustDomain}"
      data_dir = "${cfg.dataDir}"
      log_level = "${cfg.logLevel}"
      socket_path = "${cfg.socketPath}"
    }
    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "sqlite3"
          connection_string = "${cfg.dataDir}/datastore.sqlite3"
        }
      }
      KeyManager "disk" {
        plugin_data {
          keys_path = "${cfg.dataDir}/keys.json"
        }
      }
      NodeAttestor "join_token" {
        plugin_data {}
      }
  ''
  + lib.optionalString tpmAttestationEnabled ''
    NodeAttestor "tpm_devid" {
      plugin_data {
        devid_ca_path = "${cfg.tpmAttestation.devidCaPath}"
        endorsement_ca_path = "${cfg.tpmAttestation.endorsementCaPath}"
      }
    }
  ''
  + ''
    }
  '';

  spireGenerateJoinTokensApp = pkgs.writeShellApplication {
    name = "spire-generate-join-tokens";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.spire
    ];
    text = ''
      mkdir -p "${cfg.tokenDir}"
      chmod 755 "${cfg.tokenDir}"

      # Wait until the server is up
      for i in $(seq 1 60); do
        if spire-server healthcheck -socketPath ${cfg.socketPath} >/dev/null 2>&1; then
          echo "SPIRE server is ready"
          break
        fi
        echo "Waiting for SPIRE server... ($i/60)"
        sleep 1
      done

      for vm in ${lib.concatStringsSep " " cfg.spireAgentVMs}; do
        f="${cfg.tokenDir}/''${vm}.token"

        # Check if agent is already registered
        if spire-server agent list -socketPath ${cfg.socketPath} 2>/dev/null | grep -q "spiffe://${cfg.trustDomain}/agent/''${vm}"; then
          echo "Agent $vm already registered, skipping token generation"
          continue
        fi

        echo "Generating new token for $vm"
        token="$(spire-server token generate \
          -socketPath ${cfg.socketPath} \
          | awk '/^Token:/ {print $2}')"

        printf '%s\n' "$token" > "$f"
        chmod 0644 "$f"
        echo "Token written to $f"
      done
    '';
  };

  spirePublishBundleApp = pkgs.writeShellApplication {
    name = "spire-publish-bundle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.spire
    ];
    text = ''
      out="${cfg.bundleOutPath}"
      mkdir -p "$(dirname "$out")"

      # Wait until the server API socket exists and the server is ready
      for _ in $(seq 1 60); do
        if [ -S "${cfg.socketPath}" ] && spire-server healthcheck -socketPath "${cfg.socketPath}" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      if [ ! -S "${cfg.socketPath}" ]; then
        echo "ERROR: SPIRE server socket not found at ${cfg.socketPath}" >&2
        exit 1
      fi

      tmp="$(mktemp)"
      spire-server bundle show -socketPath "${cfg.socketPath}" > "$tmp"
      if [ ! -s "$tmp" ]; then
        echo "ERROR: bundle export produced empty output" >&2
        exit 1
      fi

      install -m 0644 -o root -g root "$tmp" "$out"
      rm -f "$tmp"
      echo "Wrote $out"
    '';
  };

  spireCreateWorkloadEntriesApp = pkgs.writeShellApplication {
    name = "spire-create-workload-entries";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.spire
    ];
    text = ''
      SOCKET="${cfg.socketPath}"
      TRUST_DOMAIN="${cfg.trustDomain}"
      EXPECTED_AGENTS=${toString (builtins.length cfg.spireAgentVMs)}

      echo "=== SPIRE Workload Entry Creator ==="
      echo "Expected agents: $EXPECTED_AGENTS"

      # Wait for server
      for _ in $(seq 1 60); do
        if spire-server healthcheck -socketPath "$SOCKET" >/dev/null 2>&1; then
          echo "Server ready"
          break
        fi
        sleep 1
      done

      # Wait for ALL expected agents (up to 3 minutes)
      echo "Waiting for all $EXPECTED_AGENTS agents to register..."
      AGENT_COUNT=0
      for i in $(seq 1 90); do
        AGENT_COUNT=$(spire-server agent list -socketPath "$SOCKET" 2>/dev/null | grep "SPIFFE ID" | wc -l)
        if [ "$AGENT_COUNT" -ge "$EXPECTED_AGENTS" ]; then
          echo "All agents registered: $AGENT_COUNT/$EXPECTED_AGENTS"
          break
        fi
        if [ $((i % 10)) -eq 0 ]; then
          echo "Waiting... $AGENT_COUNT/$EXPECTED_AGENTS agents [$i/90]"
        fi
        sleep 2
      done

      if [ "$AGENT_COUNT" -lt "$EXPECTED_AGENTS" ]; then
        echo "WARNING: Only $AGENT_COUNT/$EXPECTED_AGENTS agents registered after timeout"
        echo "Continuing with available agents..."
      fi

      # Get ALL agent IDs
      AGENT_IDS=$(spire-server agent list -socketPath "$SOCKET" 2>/dev/null \
        | grep "SPIFFE ID" \
        | awk -F': ' '{print $2}' \
        | tr -d ' ')

      if [ -z "$AGENT_IDS" ]; then
        echo "ERROR: No agents found"
        exit 1
      fi

      AGENT_COUNT=$(echo "$AGENT_IDS" | wc -l)
      echo ""
      echo "Creating entries for $AGENT_COUNT agents..."

      # Workload names
      WORKLOADS=( ${lib.concatMapStringsSep " " (e: lib.escapeShellArg e.name) cfg.workloadEntries} )

      # Create entries for EACH agent
      CREATED=0
      SKIPPED=0

      for PARENT_ID in $AGENT_IDS; do
        echo ""
        echo "--- Agent: $PARENT_ID ---"

        for WORKLOAD in "''${WORKLOADS[@]}"; do
          SPIFFE_ID="spiffe://$TRUST_DOMAIN/workload/$WORKLOAD"

          # Check if entry exists for this agent+workload combo
          EXISTS=$(spire-server entry show -socketPath "$SOCKET" 2>/dev/null | grep -A1 "$SPIFFE_ID" | grep "$PARENT_ID" | wc -l)

          if [ "$EXISTS" -gt 0 ]; then
            echo "  [skip] $WORKLOAD"
            SKIPPED=$((SKIPPED + 1))
          else
            echo "  [create] $WORKLOAD"
            spire-server entry create \
              -socketPath "$SOCKET" \
              -parentID "$PARENT_ID" \
              -spiffeID "$SPIFFE_ID" \
              -selector unix:user:ghaf >/dev/null 2>&1 || echo "  [FAILED] $WORKLOAD"
            CREATED=$((CREATED + 1))
          fi
        done
      done

      echo "Done: created=$CREATED skipped=$SKIPPED"
    '';
  };
in
{
  _file = ./server.nix;

  options.ghaf.security.spiffe.server = {
    enable = lib.mkEnableOption "SPIRE server";

    trustDomain = lib.mkOption {
      type = lib.types.str;
      default = "ghaf.internal";
      description = "SPIFFE trust domain served by SPIRE server";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "SPIRE server bind address";
    };

    bindPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "SPIRE server bind port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/spire/server";
      description = "SPIRE server state directory";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "INFO";
      description = "SPIRE server log level";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall for SPIRE server bind port";
    };

    spireAgentVMs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of VM names that will run spire-agent";
    };

    tokenDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/tokens";
      description = "Directory where join tokens are stored (virtiofs)";
    };

    bundleOutPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/bundle.pem";
      description = "Path where the SPIRE trust bundle is published (virtiofs)";
    };

    generateJoinTokens = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Generate join tokens for listed VMs";
    };

    publishBundle = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Publish the SPIRE trust bundle to bundleOutPath";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/spire-server/private/api.sock";
      description = "Unix socket for spire-server";
    };

    createWorkloadEntries = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Auto-create workload entries";
    };

    workloadEntries = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Workload name";
            };
            selectors = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "unix:user:ghaf" ];
              description = "Workload selectors";
            };
          };
        }
      );
      default = [ ];
      description = "Workload entries to register";
    };

    tpmAttestation = {
      enable = lib.mkEnableOption "TPM DevID attestation on SPIRE server";

      devidCaPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/spire/ca/ca.pem";
        description = "Path to the DevID CA certificate";
      };

      endorsementCaPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/spire/ca/endorsement-ca.pem";
        description = ''
          Path to TPM manufacturer endorsement key CA certificate(s).
          Used to verify TPM genuineness during DevID attestation.
          For production, bundle real manufacturer root CAs (e.g. Infineon).
          The DevID CA setup creates a placeholder here on first boot.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.spire ];

    users.groups.spire = { };
    users.users.spire = {
      isSystemUser = true;
      group = "spire";
    };

    environment.etc."spire/server.conf".text = serverConf;

    systemd.tmpfiles.rules = [
      "d /tmp/spire-server 0755 root root - -"
      "d /tmp/spire-server/private 0755 spire spire - -"
    ]
    ++ lib.optionals cfg.generateJoinTokens [
      "d ${cfg.tokenDir} 0755 root root - -"
    ];

    systemd.services.spire-server = {
      description = "SPIRE Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        User = "spire";
        Group = "spire";

        ExecStart = "${pkgs.spire}/bin/spire-server run -config /etc/spire/server.conf";

        StateDirectory = "spire/server";
        StateDirectoryMode = "0750";

        Restart = "on-failure";
        RestartSec = "2s";

        NoNewPrivileges = true;
        PrivateTmp = false;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          "/tmp/spire-server"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.bindPort ];

    systemd.services.spire-generate-join-tokens = lib.mkIf cfg.generateJoinTokens {
      description = "Generate SPIRE join tokens for Ghaf VMs";
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
        User = "root";
        ExecStart = lib.getExe spireGenerateJoinTokensApp;
      };
    };

    systemd.services.spire-publish-bundle = lib.mkIf cfg.publishBundle {
      description = "Publish SPIRE trust bundle";
      wantedBy = [ "multi-user.target" ];
      after = [ "spire-server.service" ];
      wants = [ "spire-server.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = lib.getExe spirePublishBundleApp;
      };
    };

    systemd.services.spire-create-workload-entries = lib.mkIf cfg.createWorkloadEntries {
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
        User = "root";
        ExecStart = lib.getExe spireCreateWorkloadEntriesApp;
      };
    };
  };
}
