# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  options.ghaf.logging = with lib; {
    enable = mkEnableOption "Ghaf logging system";

    client = mkEnableOption ''
      Alloy client that sends logs to admin-vm.
      Enable this on host + all VMs except admin-vm.
    '';

    server = mkEnableOption ''
      Alloy server + Loki that receives and stores logs.
      Enable this on admin-vm only.
    '';

    debug = {
      enable = mkEnableOption ''
        Include debugging tools and test scripts.
        Adds logging-server-tests on admin-vm and logging-client-tests on clients.
      '';
    };

    listener = {
      address = mkOption {
        type = types.str;
        default = "";
        description = "Admin-VM IP address for log aggregation";
      };

      port = mkOption {
        type = types.port;
        default = 9999;
        description = "Public TLS listener port (stunnel)";
      };

      backendPort = mkOption {
        type = types.port;
        default = 3101;
        description = "Backend HTTP port (Alloy behind stunnel)";
      };
    };

    remote = {
      enable = mkEnableOption "sync logs to remote Loki instance";

      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
        description = "Remote Loki push endpoint URL";
      };
    };

    local = {
      enable = mkEnableOption "local Loki instance on admin-vm";

      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Loki listen address";
      };

      listenPort = mkOption {
        type = types.port;
        default = 3100;
        description = "Loki HTTP API port";
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/loki";
        description = "Loki data storage directory";
      };

      retention = {
        enable = mkEnableOption "log retention with automatic deletion";

        defaultPeriod = mkOption {
          type = types.str;
          default = "720h"; # 30 days
          description = "Default retention period";
        };

        categoryPeriods = mkOption {
          type = types.attrsOf types.str;
          default = {
            security = "2160h"; # 90 days
            system = "720h"; # 30 days
          };
          description = "Retention periods per log category";
        };

        compactionInterval = mkOption {
          type = types.str;
          default = "10m";
          description = "Compaction interval";
        };

        deleteDelay = mkOption {
          type = types.str;
          default = "2h";
          description = "Delay before deleting marked chunks";
        };
      };
    };

    categorization = {
      enable = mkEnableOption "log categorization (security/system)";

      securityServices = mkOption {
        type = types.listOf types.str;
        default = [
          "sshd"
          "ssh"
          "polkit"
          "polkit-1"
          "audit"
          "auditd"
        ];
        description = "Services to categorize as security logs";
      };

      securityIdentifiers = mkOption {
        type = types.listOf types.str;
        default = [
          "sudo"
          "audit"
          "polkitd"
          "sshd"
        ];
        description = "Syslog identifiers for security logs";
      };
    };

    journalRetention = {
      enable = mkEnableOption "local systemd journal retention";

      maxRetentionDays = mkOption {
        type = types.int;
        default = 1;
        description = "Maximum days to retain journal logs locally";
      };

      maxDiskUsage = mkOption {
        type = types.str;
        default = "500M";
        description = "Maximum disk space for journal logs";
      };
    };

    tls = {
      caFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "CA certificate for mTLS";
      };

      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Client/server certificate";
      };

      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Private key";
      };

      remoteCAFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "CA for remote Loki (if different)";
      };

      serverName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "TLS server_name (SNI) for remote endpoint";
      };

      minVersion = mkOption {
        type = types.enum [
          "TLS12"
          "TLS13"
        ];
        default = "TLS12";
        description = "Minimum TLS version";
      };

      terminator = {
        verifyClients = mkOption {
          type = types.bool;
          default = true;
          description = "Require client certificates (admin-vm)";
        };
      };
    };

    identifierFilePath = mkOption {
      type = types.path;
      default = "/etc/common/device-id";
      description = "Device identifier file path";
    };
  };

  config = lib.mkIf config.ghaf.logging.enable {
    # Assertions
    assertions = [
      {
        assertion = config.ghaf.logging.listener.address != "";
        message = "ghaf.logging.listener.address must be set";
      }
      {
        assertion = config.ghaf.logging.remote.enable -> config.ghaf.logging.remote.endpoint != null;
        message = "remote.endpoint required when remote.enable is true";
      }
      {
        assertion = config.ghaf.logging.listener.port != config.ghaf.logging.listener.backendPort;
        message = "listener.port and backendPort must differ";
      }
      {
        assertion = (config.ghaf.logging.tls.certFile != null) && (config.ghaf.logging.tls.keyFile != null);
        message = "TLS certFile and keyFile must be set";
      }
    ];

    # Set default listener address from networking config
    ghaf.logging.listener.address = lib.mkDefault (
      if config.ghaf.networking.hosts ? admin-vm then config.ghaf.networking.hosts.admin-vm.ipv4 else ""
    );

    # Enable features by default
    ghaf.logging.local.enable = lib.mkDefault true;
    ghaf.logging.local.retention.enable = lib.mkDefault true;
    ghaf.logging.categorization.enable = lib.mkDefault true;
    ghaf.logging.journalRetention.enable = lib.mkDefault true;
  };
}
