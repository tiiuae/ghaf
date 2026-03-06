# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# SPIRE Agent Module
#
# Runs a SPIRE agent on each VM. Supports two attestation modes:
# - join_token: for app VMs (emulated TPM, no hardware root)
# - tpm_devid: for system VMs with hardware TPM passthrough
#
# The attestation mode is selected based on cfg.attestationMode.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.agent;

  useTpmDevid = cfg.attestationMode == "tpm_devid";

  # Common agent config (shared between tpm_devid and join_token modes)
  agentConfCommon = ''
    agent {
      data_dir = "${cfg.dataDir}"
      log_level = "${cfg.logLevel}"
      server_address = "${cfg.serverAddress}"
      server_port = ${toString cfg.serverPort}
      trust_domain = "${cfg.trustDomain}"
      trust_bundle_path = "${cfg.trustBundlePath}"
      socket_path = "${cfg.socketPath}"
  '';

  agentConfTpmDevid = agentConfCommon + ''
    }

    plugins {
      NodeAttestor "tpm_devid" {
        plugin_data {
          tpm_device_path = "${cfg.tpmDevid.devicePath}"
          devid_cert_path = "${cfg.tpmDevid.certPath}"
          devid_priv_path = "${cfg.tpmDevid.privPath}"
          devid_pub_path = "${cfg.tpmDevid.pubPath}"
        }
      }

      WorkloadAttestor "unix" {
        plugin_data {}
      }

      KeyManager "disk" {
        plugin_data {
          directory = "${cfg.dataDir}/keys"
        }
      }
    }
  '';

  agentConfJoinToken = agentConfCommon + ''
    join_token_file = "${cfg.joinTokenFile}"
    }

    plugins {
      NodeAttestor "join_token" {
        plugin_data {}
      }

      WorkloadAttestor "unix" {
        plugin_data {}
      }

      KeyManager "disk" {
        plugin_data {
          directory = "${cfg.dataDir}/keys"
        }
      }
    }
  '';

  # For tpm_devid mode, generate both configs and select at runtime

  # Runtime config selector: checks if DevID files exist, falls back to join_token
  agentConfSelector = pkgs.writeShellScript "spire-agent-select-config" ''
    export TPM2TOOLS_TCTI="device:${cfg.tpmDevid.devicePath}"

    ek_index_available() {
      local idx="$1"
      ${pkgs.coreutils}/bin/timeout -k 2 5 ${pkgs.tpm2-tools}/bin/tpm2_nvreadpublic "$idx" >/dev/null 2>&1
    }

    tpm_in_lockout() {
      ${pkgs.coreutils}/bin/timeout -k 2 5 ${pkgs.tpm2-tools}/bin/tpm2_getcap properties-variable 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "inLockout:[[:space:]]*1"
    }

    if [ "${toString useTpmDevid}" = "1" ]; then
      if [ -f "${cfg.tpmDevid.certPath}" ] && \
         [ -f "${cfg.tpmDevid.privPath}" ] && \
         [ -f "${cfg.tpmDevid.pubPath}" ]; then
        if tpm_in_lockout; then
          echo "TPM is in DA lockout mode, falling back to join_token attestation"
          ln -sf /etc/spire/agent-join-token.conf /run/spire/agent.conf
          exit 0
        fi

        if ! ek_index_available 0x01C00002 && ! ek_index_available 0x01C0000A; then
          echo "EK cert NV indices are missing, falling back to join_token attestation"
          ln -sf /etc/spire/agent-join-token.conf /run/spire/agent.conf
          exit 0
        fi

        if [ -d "${cfg.dataDir}" ] && grep -Rqs "/spire/agent/join_token/" "${cfg.dataDir}" 2>/dev/null; then
          echo "Join-token SVID cache detected, resetting SPIRE agent state for tpm_devid"
          for entry in "${cfg.dataDir}"/* "${cfg.dataDir}"/.[!.]* "${cfg.dataDir}"/..?*; do
            [ -e "$entry" ] || continue
            rm -rf "$entry"
          done
        fi
        echo "DevID files found, using tpm_devid attestation"
        ln -sf /etc/spire/agent-tpm-devid.conf /run/spire/agent.conf
      else
        echo "DevID files not found, falling back to join_token attestation"
        ln -sf /etc/spire/agent-join-token.conf /run/spire/agent.conf
      fi
    else
      ln -sf /etc/spire/agent-join-token.conf /run/spire/agent.conf
    fi
  '';

  tpmReadyWait = pkgs.writeShellScript "spire-agent-wait-tpm" ''
    # Add small deterministic startup jitter so system VMs do not hammer TPM simultaneously.
    if [ -r /etc/hostname ]; then
      seed=$(${pkgs.coreutils}/bin/cksum /etc/hostname | ${pkgs.coreutils}/bin/cut -d' ' -f1)
      delay=$((seed % 8))
      ${pkgs.coreutils}/bin/sleep "$delay"
    fi

    export TPM2TOOLS_TCTI="device:${cfg.tpmDevid.devicePath}"

    ready_seq=0
    for attempt in $(seq 1 30); do
      if ${pkgs.coreutils}/bin/timeout -k 1 3 ${pkgs.tpm2-tools}/bin/tpm2_getcap properties-fixed >/dev/null 2>&1; then
        ready_seq=$((ready_seq + 1))
        if [ "$ready_seq" -ge 2 ]; then
          exit 0
        fi
      else
        ready_seq=0
      fi

      ${pkgs.coreutils}/bin/sleep 1
    done

    echo "WARNING: TPM readiness probe timed out; starting SPIRE agent anyway"
    exit 0
  '';
in
{
  _file = ./agent.nix;

  options.ghaf.security.spiffe.agent = {
    enable = lib.mkEnableOption "SPIRE agent";

    trustDomain = lib.mkOption {
      type = lib.types.str;
      default = "ghaf.internal";
      description = "SPIFFE trust domain expected from the server";
    };

    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "SPIRE server address reachable from this VM";
    };

    serverPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "SPIRE server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/spire/agent";
      description = "SPIRE agent state directory";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "INFO";
      description = "SPIRE agent log level";
    };

    trustBundlePath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/bundle.pem";
      description = "Path to the SPIRE trust bundle PEM file";
    };

    joinTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/spire/tokens/agent.token";
      description = "Path to a file containing a join token";
    };

    socketPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/spire/agent.sock";
      description = "SPIRE Agent API socket path";
    };

    attestationMode = lib.mkOption {
      type = lib.types.enum [
        "join_token"
        "tpm_devid"
      ];
      default = "join_token";
      description = "Node attestation mode: join_token (app VMs) or tpm_devid (system VMs with TPM)";
    };

    tpmDevid = {
      devicePath = lib.mkOption {
        type = lib.types.str;
        default = "/dev/tpmrm0";
        description = "Path to the TPM device used for tpm_devid attestation";
      };
      certPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/spire/devid/devid.pem";
        description = "Path to the DevID certificate";
      };
      privPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/spire/devid/devid.priv";
        description = "Path to the DevID TPM private blob";
      };
      pubPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/spire/devid/devid.pub";
        description = "Path to the DevID TPM public blob";
      };
    };

    workloadApiGroup = lib.mkOption {
      type = lib.types.str;
      default = "spiffe";
      description = "Group allowed to access the SPIRE Agent API socket";
    };

    workloadApiUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ghaf" ];
      description = "Users added to workloadApiGroup for SPIRE Workload API access";
    };

    commonMountPath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common";
      description = "Path to the common virtiofs mount (VMs use /etc/common, host uses /persist/common)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.spire ];

    users.groups = {
      spire = { };
      "${cfg.workloadApiGroup}" = { };
    };

    users.users = {
      spire = {
        isSystemUser = true;
        group = "spire";
        extraGroups = lib.optionals useTpmDevid [
          config.security.tpm2.tssGroup or "tss"
        ];
      };
    }
    // (lib.genAttrs cfg.workloadApiUsers (_: {
      extraGroups = lib.mkAfter [ cfg.workloadApiGroup ];
    }));

    environment.etc."spire/agent-join-token.conf".text = agentConfJoinToken;
    environment.etc."spire/agent-tpm-devid.conf" = lib.mkIf useTpmDevid {
      text = agentConfTpmDevid;
    };

    # Own /run/spire via tmpfiles with group access for spiffe users
    systemd.tmpfiles.rules = [
      "d /run/spire 2750 spire ${cfg.workloadApiGroup} - -"
    ];

    systemd.services.spire-agent = {
      description = "SPIRE Agent";
      wantedBy = [ "multi-user.target" ];

      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig = {
        RequiresMountsFor = [ cfg.commonMountPath ];
      };

      serviceConfig = {
        PermissionsStartOnly = true;

        User = "spire";
        Group = "spire";

        UMask = "007";

        SupplementaryGroups = [
          cfg.workloadApiGroup
        ]
        ++ lib.optionals useTpmDevid [
          config.security.tpm2.tssGroup or "tss"
        ];

        ExecStartPre = lib.optionals useTpmDevid [ "+${tpmReadyWait}" ] ++ [ "+${agentConfSelector}" ];
        ExecStart = "${pkgs.spire}/bin/spire-agent run -config /run/spire/agent.conf";

        StateDirectory = "spire/agent";
        StateDirectoryMode = "0750";

        Restart = "on-failure";
        RestartSec = "2s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          "/run/spire"
        ]
        ++ lib.optionals useTpmDevid [
          cfg.tpmDevid.devicePath
        ];
      };
    };
  };
}
