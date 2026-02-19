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

  agentConf = ''
    agent {
      data_dir = "${cfg.dataDir}"
      log_level = "${cfg.logLevel}"
      server_address = "${cfg.serverAddress}"
      server_port = ${toString cfg.serverPort}
      trust_domain = "${cfg.trustDomain}"
      trust_bundle_path = "${cfg.trustBundlePath}"
      socket_path = "${cfg.socketPath}"
  ''
  + lib.optionalString (!useTpmDevid) ''
    join_token_file = "${cfg.joinTokenFile}"
  ''
  + ''
    }

    plugins {
  ''
  + (
    if useTpmDevid then
      ''
        NodeAttestor "tpm_devid" {
          plugin_data {
            devid_cert_path = "${cfg.tpmDevid.certPath}"
            devid_priv_path = "${cfg.tpmDevid.privPath}"
            devid_pub_path = "${cfg.tpmDevid.pubPath}"
          }
        }
      ''
    else
      ''
        NodeAttestor "join_token" {
          plugin_data {}
        }
      ''
  )
  + ''

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

    environment.etc."spire/agent.conf".text = agentConf;

    # Own /run/spire via tmpfiles with group access for spiffe users
    systemd.tmpfiles.rules = [
      "d /run/spire 2750 spire ${cfg.workloadApiGroup} - -"
    ];

    systemd.services.spire-agent = {
      description = "SPIRE Agent";
      wantedBy = [ "multi-user.target" ];

      requires = [ "network-online.target" ];
      after = [
        "network-online.target"
      ]
      ++ lib.optionals useTpmDevid [ "spire-devid-provision.service" ];
      wants = [ "network-online.target" ];
      unitConfig = {
        RequiresMountsFor = [ "/etc/common" ];
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

        ExecStart = "${pkgs.spire}/bin/spire-agent run -config /etc/spire/agent.conf";

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
          "/dev/tpmrm0"
        ];
      };
    };
  };
}
