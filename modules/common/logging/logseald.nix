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
    escapeShellArgs
    hasAttrByPath
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    optionals
    types
    ;
  cfg = config.ghaf.logging.logseald;
  enabled = cfg.producer.enable || cfg.sealer.enable;
  givcHostEnabled = config.ghaf.givc.host.enable;
  needsGivcMount = config.ghaf.givc.enable && !givcHostEnabled;
  hasGhafFirewall = hasAttrByPath [ "ghaf" "firewall" "extra" ] options;
  hasGivcUserTlsAccess = hasAttrByPath [ "givc" "sysvm" "enableUserTlsAccess" ] options;
  wildcardSealerAddresses = [
    ""
    "0.0.0.0"
    "::"
    "[::]"
  ];
  sealerFirewallRules =
    if hasGhafFirewall then
      map (
        address:
        "-p tcp -s ${address} --dport ${toString cfg.endpoint.port} -m conntrack --ctstate NEW -j ${config.ghaf.firewall.chainNamePrefix}conncheck-accept"
      ) cfg.sealer.allowedProducerAddresses
    else
      [ ];
  credentialDirectory = service: "/run/credentials/${service}.service";
  producerCredentialDirectory = credentialDirectory "logseald-producer";
  sealerCredentialDirectory = credentialDirectory "logseald-sealer";
  journalPermissions = pkgs.writeText "logseald-journal-permissions.conf" ''
    z /var/log/journal 2755 root systemd-journal -
    z /var/log/journal/%m 2755 root systemd-journal -
    z /run/log/journal 2755 root systemd-journal -
    z /run/log/journal/%m 2755 root systemd-journal -
    z /var/log/journal/%m/*.journal 0640 root systemd-journal -
    z /var/log/journal/%m/*.journal~ 0640 root systemd-journal -
    z /run/log/journal/%m/*.journal 0640 root systemd-journal -
    z /run/log/journal/%m/*.journal~ 0640 root systemd-journal -
  '';
  commonHardening = {
    CapabilityBoundingSet = "";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    UMask = "0027";
  };
  revokedPeerKeysFile = pkgs.writeText "logseald-revoked-peer-keys" (
    lib.concatStringsSep "\n" cfg.tls.revokedPeerKeys
  );
  storageOptions = bytes: {
    maxStateBytes = mkOption {
      type = types.ints.positive;
      default = bytes;
      description = "Evidence byte budget. Producers expire acknowledged history to admit new blocks, but never discard pending blocks. Compact sealers reserve two checkpoint generations within this budget.";
    };
    maxStateEntries = mkOption {
      type = types.ints.positive;
      default = 100000;
      description = "Maximum producer evidence entries, or compact sealer chain identities (also capped at 256).";
    };
  };
  tlsCredentials = directory: [
    "--cert"
    "${directory}/certificate.pem"
    "--key"
    "${directory}/key.pem"
    "--ca"
    "${directory}/ca-cert.pem"
    "--revoked-peer-keys"
    (toString revokedPeerKeysFile)
  ];
in
{
  _file = ./logseald.nix;

  options.ghaf.logging.logseald = {
    producer = storageOptions (256 * 1024 * 1024) // {
      windowEntries = mkOption {
        type = types.ints.unsigned;
        default = 20000;
        description = "Maximum retained sealed blocks. Older acknowledged blocks expire by sequence, never wall time. Zero disables expiry. The byte budget can shorten the window.";
      };
      memoryMaxMiB = mkOption {
        type = types.ints.between 256 65536;
        default = 256;
        description = "Hard memory limit including journalctl. Large historical v1 artifacts may need a larger startup budget; provision VM RAM before raising this.";
      };
      enable = mkEnableOption "clock-independent producer-side journal sealing";
      stateDirectory = mkOption {
        type = types.str;
        default =
          if config.ghaf.type == "host" then
            "/persist/common/logseald/producer"
          else
            "/var/lib/logseald/producer";
        defaultText = ''
          "/persist/common/logseald/producer" on the host,
          "/var/lib/logseald/producer" in VMs
        '';
        description = "Durable producer queue, sealed sidecars and pinned sealer key.";
      };
      sourceName = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = "config.networking.hostName";
        description = "Source annotation included in every producer block.";
      };
      blockRecords = mkOption {
        type = types.ints.between 1 4096;
        default = 256;
        description = "Maximum journal records in one sealing block.";
      };
      blockIntervalSeconds = mkOption {
        type = types.ints.positive;
        default = 5;
        description = "Maximum time records remain only in the in-memory block builder.";
      };
      maxPendingBlocks = mkOption {
        type = types.ints.positive;
        default = 64;
        description = ''
          Maximum durable blocks queued while admin-vm is unavailable. At the
          limit, logseald stops consuming journalctl until space is available;
          journald remains the authoritative retention/backpressure layer.
        '';
      };
      retryIntervalSeconds = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "Interval between attempts to submit the oldest queued block.";
      };
    };

    sealer = storageOptions (1024 * 1024 * 1024) // {
      memoryMaxMiB = mkOption {
        type = types.ints.between 384 65536;
        default = 384;
        description = "Hard memory limit. Large historical v1 artifacts may need a larger startup budget; provision admin-vm RAM before raising this.";
      };
      maxChainBytes = mkOption {
        type = types.ints.positive;
        default = 128 * 1024 * 1024;
        description = "Legacy-ledger migration validation limit per producer. Compact state retains one signed head per identity instead.";
      };
      maxChainEntries = mkOption {
        type = types.ints.positive;
        default = 20000;
        description = "Legacy-ledger migration validation limit per producer. Does not limit lifetime seals in compact mode.";
      };
      enable = mkEnableOption "central logseald signing and ordering service";
      address = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address on which the admin-vm sealer listens.";
      };
      stateDirectory = mkOption {
        type = types.str;
        default = "/var/lib/logseald/sealer";
        description = "Durable sealer private key and append-only ledger.";
      };
      allowedProducerAddresses = mkOption {
        type = types.listOf (types.strMatching "([0-9]{1,3}[.]){3}[0-9]{1,3}");
        default = [ ];
        description = "Internal IPv4 addresses allowed to connect to the sealer.";
      };
    };

    endpoint = {
      address = mkOption {
        type = types.str;
        default = config.ghaf.logging.listener.address;
        defaultText = "config.ghaf.logging.listener.address";
        description = "Address producers use to reach the admin-vm sealer.";
      };
      port = mkOption {
        type = types.port;
        default = 59631;
        description = "Logseald mTLS port.";
      };
      serverName = mkOption {
        type = types.str;
        default = "admin-vm";
        description = "DNS identity expected in the admin-vm GIVC certificate.";
      };
    };

    tls = {
      revokedPeerKeys = mkOption {
        type = types.listOf (types.strMatching "spki-sha256:[0-9a-f]{64}");
        default = [ ];
        description = "Denied peer leaf public-key identities, enforced without time or network access. Deploy to all peers and restart logseald to terminate established sessions.";
      };
      caFile = mkOption {
        type = types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "GIVC CA bundle used for logseald mutual TLS.";
      };
      certFile = mkOption {
        type = types.path;
        default = "/etc/givc/cert.pem";
        description = "This producer or sealer's GIVC certificate.";
      };
      keyFile = mkOption {
        type = types.path;
        default = "/etc/givc/key.pem";
        description = "This producer or sealer's GIVC private key.";
      };
      timePolicy = mkOption {
        type = types.enum [
          "static-cert"
          "wall-clock"
        ];
        default = "static-cert";
        description = ''
          Certificate-time policy. static-cert still verifies the CA chain,
          peer name and key usage, but selects a time inside the certificate
          validity interval instead of trusting the unsynchronised wall clock.
        '';
      };
    };
  };

  config = mkIf enabled (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.producer.windowEntries <= cfg.producer.maxStateEntries;
          message = "logseald producer.windowEntries must not exceed producer.maxStateEntries.";
        }
        {
          assertion = config.ghaf.logging.enable;
          message = "ghaf.logging.logseald requires ghaf.logging.enable.";
        }
        {
          assertion = config.ghaf.givc.enable && config.ghaf.givc.enableTls;
          message = "ghaf.logging.logseald currently requires the GIVC PKI with TLS enabled.";
        }
        {
          assertion = (!cfg.producer.enable) || cfg.endpoint.address != "";
          message = "ghaf.logging.logseald.endpoint.address must be set for producers.";
        }
        {
          assertion = (!cfg.producer.enable) || cfg.endpoint.serverName != "";
          message = "ghaf.logging.logseald.endpoint.serverName must identify the GIVC sealer certificate.";
        }
        {
          assertion =
            (!cfg.sealer.enable)
            || (!hasGhafFirewall)
            || (
              cfg.sealer.address == cfg.endpoint.address
              && !builtins.elem cfg.sealer.address wildcardSealerAddresses
            );
          message = "The production logseald sealer must bind only to its internal producer endpoint address.";
        }
        {
          assertion =
            (!cfg.sealer.enable)
            || (!hasGhafFirewall)
            || (!config.ghaf.firewall.enable)
            || cfg.sealer.allowedProducerAddresses != [ ];
          message = "The production logseald sealer requires an explicit producer address allowlist.";
        }
        {
          assertion =
            (!cfg.sealer.enable) || (!hasGivcUserTlsAccess) || (!config.givc.sysvm.enableUserTlsAccess);
          message = "The logseald sealer is incompatible with user-readable GIVC private keys.";
        }
      ];

      users.groups."logseald-producer" = { };
      users.users."logseald-producer" = {
        isSystemUser = true;
        group = "logseald-producer";
        description = "Ghaf log sealing producer";
      };
      users.groups."logseald-sealer" = { };
      users.users."logseald-sealer" = {
        isSystemUser = true;
        group = "logseald-sealer";
        description = "Ghaf log sealing authority";
      };

      environment.systemPackages = [ pkgs.logseald ];
      ghaf.storagevm.directories = mkIf (config.ghaf.storagevm.enable && config.ghaf.type != "host") [
        {
          directory = "/var/lib/logseald";
          user = "root";
          group = "root";
          mode = "0711";
        }
      ];
    }

    (mkIf cfg.producer.enable {
      systemd.tmpfiles.rules = [
        "d ${dirOf cfg.producer.stateDirectory} 0711 root root -"
        "d ${cfg.producer.stateDirectory} 0750 logseald-producer logseald-producer -"
      ];
      systemd.services.logseald-journal-permissions = {
        description = "Prepare read-only journal access for logseald";
        after = [
          "systemd-tmpfiles-setup.service"
          "systemd-journal-flush.service"
        ];
        requires = [ "systemd-tmpfiles-setup.service" ];
        partOf = [ "systemd-tmpfiles-setup.service" ];
        before = [ "logseald-producer.service" ];
        unitConfig.RequiresMountsFor = [ "/var/log/journal" ];
        serviceConfig = commonHardening // {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
          Group = "root";
          CapabilityBoundingSet = [
            "CAP_CHOWN"
            "CAP_DAC_OVERRIDE"
            "CAP_DAC_READ_SEARCH"
            "CAP_FOWNER"
            "CAP_FSETID"
          ];
          RestrictSUIDSGID = false;
          PrivateNetwork = true;
          ReadWritePaths = [
            "-/var/log/journal"
            "-/run/log/journal"
          ];
          ExecStart = "${pkgs.systemd}/bin/systemd-tmpfiles --create ${journalPermissions}";
        };
      };
      systemd.services.logseald-producer = {
        description = "Clock-independent journal block producer";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-journald.service"
          "logseald-journal-permissions.service"
          "network.target"
        ]
        ++ optionals givcHostEnabled [ "givc-key-setup.service" ];
        requires = [ "logseald-journal-permissions.service" ];
        partOf = [ "logseald-journal-permissions.service" ];
        wants = optionals givcHostEnabled [ "givc-key-setup.service" ];
        unitConfig = optionalAttrs needsGivcMount {
          RequiresMountsFor = [ "/etc/givc" ];
        };
        serviceConfig = commonHardening // {
          User = "logseald-producer";
          Group = "logseald-producer";
          SupplementaryGroups = [ "systemd-journal" ];
          ReadWritePaths = [ cfg.producer.stateDirectory ];
          Restart = "on-failure";
          RestartSec = "2s";
          RestartPreventExitStatus = [ 75 ];
          MemoryHigh = "192M";
          MemoryMax = "${toString cfg.producer.memoryMaxMiB}M";
          MemorySwapMax = 0;
          Environment = [
            "GOMEMLIMIT=128MiB"
            "GOMAXPROCS=2"
          ];
          LoadCredential = [
            "certificate.pem:${cfg.tls.certFile}"
            "key.pem:${cfg.tls.keyFile}"
            "ca-cert.pem:${cfg.tls.caFile}"
          ];
          ExecStart = escapeShellArgs (
            [
              (lib.getExe pkgs.logseald)
              "producer"
              "--state-dir"
              cfg.producer.stateDirectory
              "--max-state-bytes"
              (toString cfg.producer.maxStateBytes)
              "--max-state-entries"
              (toString cfg.producer.maxStateEntries)
              "--window-entries"
              (toString cfg.producer.windowEntries)
              "--source"
              cfg.producer.sourceName
              "--sealer-url"
              "https://${cfg.endpoint.address}:${toString cfg.endpoint.port}/v1/seal"
              "--server-name"
              cfg.endpoint.serverName
              "--tls-time-policy"
              cfg.tls.timePolicy
              "--journalctl"
              "${pkgs.systemd}/bin/journalctl"
              "--block-records"
              (toString cfg.producer.blockRecords)
              "--block-interval"
              "${toString cfg.producer.blockIntervalSeconds}s"
              "--max-pending-blocks"
              (toString cfg.producer.maxPendingBlocks)
              "--retry-interval"
              "${toString cfg.producer.retryIntervalSeconds}s"
            ]
            ++ tlsCredentials producerCredentialDirectory
          );
        };
      };
    })

    (mkIf cfg.sealer.enable (mkMerge [
      {
        users.groups."logseald-proxy" = { };
        users.users."logseald-proxy" = {
          isSystemUser = true;
          group = "logseald-proxy";
          description = "Ghaf log sealing socket proxy";
        };
        systemd.tmpfiles.rules = [
          "d ${dirOf cfg.sealer.stateDirectory} 0711 root root -"
          "d ${cfg.sealer.stateDirectory} 0700 logseald-sealer logseald-sealer -"
          "d /run/logseald-sealer 0750 logseald-sealer logseald-proxy -"
        ];
        systemd.sockets.logseald-sealer = {
          description = "Clock-independent journal block sealer socket";
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "${cfg.sealer.address}:${toString cfg.endpoint.port}" ];
          socketConfig = {
            Accept = false;
            Backlog = 128;
            FileDescriptorName = "logseald";
            FreeBind = true;
            ReusePort = false;
            Service = "logseald-sealer-proxy.service";
          };
        };
        systemd.services.logseald-sealer-proxy = {
          description = "Clock-independent journal block sealer TCP proxy";
          requires = [ "logseald-sealer.socket" ];
          after = [ "logseald-sealer.socket" ];
          serviceConfig = commonHardening // {
            User = "logseald-proxy";
            Group = "logseald-proxy";
            Sockets = [ "logseald-sealer.socket" ];
            StandardOutput = "null";
            StandardError = "null";
            ExecStart = escapeShellArgs [
              "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd"
              "--connections-max=16"
              "--exit-idle-time=30s"
              "/run/logseald-sealer/sealer.sock"
            ];
          };
        };
        systemd.services.logseald-sealer = {
          description = "Clock-independent journal block sealer";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ] ++ optionals givcHostEnabled [ "givc-key-setup.service" ];
          wants = optionals givcHostEnabled [ "givc-key-setup.service" ];
          before = [ "logseald-producer.service" ];
          unitConfig = optionalAttrs needsGivcMount {
            RequiresMountsFor = [ "/etc/givc" ];
          };
          serviceConfig = commonHardening // {
            User = "logseald-sealer";
            # Assign new sockets to the proxy group without setgid inheritance.
            Group = "logseald-proxy";
            ReadWritePaths = [
              cfg.sealer.stateDirectory
              "/run/logseald-sealer"
            ];
            Restart = "on-failure";
            RestartSec = "2s";
            RestartPreventExitStatus = [ 75 ];
            MemoryHigh = "256M";
            MemoryMax = "${toString cfg.sealer.memoryMaxMiB}M";
            MemorySwapMax = 0;
            Environment = [
              "GOMEMLIMIT=192MiB"
              "GOMAXPROCS=2"
            ];
            LoadCredential = [
              "certificate.pem:${cfg.tls.certFile}"
              "key.pem:${cfg.tls.keyFile}"
              "ca-cert.pem:${cfg.tls.caFile}"
            ];
            ExecStart = escapeShellArgs (
              [
                (lib.getExe pkgs.logseald)
                "sealer"
                "--compact-state=true"
                "--state-dir"
                cfg.sealer.stateDirectory
                "--max-state-bytes"
                (toString cfg.sealer.maxStateBytes)
                "--max-state-entries"
                (toString cfg.sealer.maxStateEntries)
                "--max-chain-bytes"
                (toString cfg.sealer.maxChainBytes)
                "--max-chain-entries"
                (toString cfg.sealer.maxChainEntries)
                "--listen"
                "unix:/run/logseald-sealer/sealer.sock"
                "--tls-time-policy"
                cfg.tls.timePolicy
              ]
              ++ tlsCredentials sealerCredentialDirectory
            );
          };
        };
      }
      (optionalAttrs hasGhafFirewall {
        ghaf.firewall.extra.input.filter = sealerFirewallRules;
      })
      (optionalAttrs (!hasGhafFirewall) {
        networking.firewall.allowedTCPPorts = [ cfg.endpoint.port ];
      })
    ]))
  ]);
}
