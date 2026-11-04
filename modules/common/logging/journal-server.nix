# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
  cfg = config.ghaf.logging.journalServer;
  retention = config.ghaf.logging.journalRetention;
  givcEnabled = config.ghaf.givc.enable;
  givcHostEnabled = config.ghaf.givc.host.enable;
  needsGivcMount = givcEnabled && !givcHostEnabled;
  producers = lib.remove config.networking.hostName (builtins.attrNames config.ghaf.networking.hosts);
  unit = "ghaf-journal-receiver";
  logDirectory = "/var/log/ghaf-journal";
  remote = lib.getExe pkgs.ghaf-journal-remote;
  receiver = pkgs.writeShellApplication {
    name = "start-journal-receiver";
    text = ''
      exec ${remote} --listen-https=0.0.0.0:${toString config.ghaf.logging.listener.port} \
        --split-mode=none --output=${logDirectory}/shared/remote.journal \
        --key="$CREDENTIALS_DIRECTORY/key" --cert="$CREDENTIALS_DIRECTORY/cert" \
        --trust="$CREDENTIALS_DIRECTORY/ca" \
        ${lib.escapeShellArgs (
          lib.optionals retention.enable [
            "--max-use=${retention.maxDiskUsage}"
            "--max-file-size=100M"
            "--max-retention=${retention.maxRetention}"
            "--max-file-age=${retention.MaxFileSec}"
          ]
          ++ map (name: "--authenticated-source=${name}") producers
        )}
    '';
  };
  tlsPolicy = pkgs.writeText "journal-receiver-tls.conf" ''
    [overrides]
    disabled-version = tls1.0
    disabled-version = tls1.1
    disabled-version = ssl3.0
  '';
  hardening = {
    User = unit;
    Group = "systemd-journal";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ logDirectory ];
    ProtectHome = true;
    PrivateDevices = true;
    PrivateTmp = true;
    CapabilityBoundingSet = "";
    UMask = "0027";
    LogLevelMax = "notice";
    # Keep unclassified shell errors visible through the notice-level filter.
    SyslogLevel = "warning";
  };

  hasGhafFw = options ? ghaf.firewall;
in
{
  _file = ./journal-server.nix;

  imports = [
    (lib.mkRemovedOptionModule [
      "ghaf"
      "logging"
      "journalServer"
      "tls"
      "terminator"
      "backendPort"
    ] "Journal ingestion now uses a single authenticated TLS receiver.")
  ];

  options.ghaf.logging.journalServer = {
    enable = mkEnableOption "Logs aggregator server";

    tls = {
      caFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "Required CA bundle for verifying journal sender certificates.";
      };
      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Receiver certificate (PEM) used for mTLS.";
      };
      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Receiver private key (PEM) used for mTLS.";
      };

      terminator = {
        verifyClients = mkOption {
          type = types.bool;
          default = true;
          description = "Require client certificates (mTLS).";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.tls.certFile != null) && (cfg.tls.keyFile != null);
        message = "Please set ghaf.logging.journalServer.tls.certFile and tls.keyFile.";
      }
      {
        assertion = cfg.tls.terminator.verifyClients && cfg.tls.caFile != null;
        message = "Journal ingestion requires client certificate verification and a trusted CA.";
      }
      {
        assertion =
          producers != [ ] && lib.all (name: builtins.match "[a-z0-9][a-z0-9-]{0,62}" name != null) producers;
        message = "Journal ingestion requires known producers with lowercase DNS identities.";
      }
    ];

    services.journald.remote.enable = lib.mkForce false;
    users.users.${unit} = {
      isSystemUser = true;
      group = "systemd-journal";
    };
    systemd.services.${unit} = {
      description = "Native journal receiver with authenticated VM sources";
      wantedBy = [ "multi-user.target" ];
      after = [
        "systemd-tmpfiles-setup.service"
      ]
      ++ lib.optionals givcHostEnabled [ "givc-key-setup.service" ];
      unitConfig.RequiresMountsFor = [ logDirectory ] ++ lib.optional needsGivcMount "/etc/givc";
      environment = {
        SYSTEMD_LOG_LEVEL = "notice";
        GNUTLS_SYSTEM_PRIORITY_FILE = tlsPolicy;
        GNUTLS_SYSTEM_PRIORITY_FAIL_ON_INVALID = "1";
      };
      serviceConfig = hardening // {
        LoadCredential = [
          "cert:${cfg.tls.certFile}"
          "key:${cfg.tls.keyFile}"
          "ca:${cfg.tls.caFile}"
        ];
        ExecStart = lib.getExe receiver;
        Restart = "on-failure";
      };
    };
    systemd.tmpfiles.rules = [
      "d ${logDirectory} 0750 root systemd-journal -"
      "d ${logDirectory}/shared 2750 ${unit} systemd-journal -"
    ];

    ghaf = {
      storagevm = lib.optionalAttrs (options ? ghaf.storagevm.directories) {
        directories = lib.mkIf config.ghaf.storagevm.enable [ logDirectory ];
      };
    }
    # Every Ghaf host uploads its journal here.
    // lib.optionalAttrs hasGhafFw {
      firewall.allowedTCPPorts = [
        {
          inherit (config.ghaf.logging.listener) port;
          from = lib.attrNames config.ghaf.networking.hosts;
        }
      ];
    };

    networking.firewall.allowedTCPPorts = [ config.ghaf.logging.listener.port ];

  };
}
