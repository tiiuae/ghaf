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
    optionalString
    ;
  cfg = config.ghaf.logging.journalClient;
  inherit (config.ghaf.logging) listener;
  givcEnabled = config.ghaf.givc.enable;
  givcHostEnabled = config.ghaf.givc.host.enable;
  needsGivcMount = givcEnabled && !givcHostEnabled;
  hasStructuredJournald = options.services.journald ? settings;

  # The uploader starts before the receiver on admin-vm is listening, fails with
  # "Failed to connect to <addr>:<port> after 0 ms: Could not connect to server",
  # and is only rescued by its restart.
  endpointHostPort = builtins.match "https?://([^/:]+):([0-9]+).*" cfg.endpoint;
  waitForListener = pkgs.writeShellApplication {
    name = "wait-for-journal-listener";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
    ];
    text = ''
      host=${lib.escapeShellArg (builtins.elemAt endpointHostPort 0)}
      port=${lib.escapeShellArg (builtins.elemAt endpointHostPort 1)}
      for _ in $(seq 1 60); do
        if openssl s_client -connect "$host:$port" \
             -cert ${lib.escapeShellArg cfg.tls.certFile} \
             -key ${lib.escapeShellArg cfg.tls.keyFile} \
             ${optionalString (cfg.tls.caFile != null) "-CAfile ${lib.escapeShellArg cfg.tls.caFile}"} \
             </dev/null >/dev/null 2>&1; then
          exit 0
        fi
        sleep 1
      done
      echo "journal-upload: $host:$port did not complete a TLS handshake in 60s;" \
           "starting anyway" >&2
    '';
  };
in
{
  _file = ./journal-client.nix;

  options.ghaf.logging.journalClient = {
    enable = mkEnableOption "Journal uploader client service";
    endpoint = mkOption {
      description = ''
        Assign endpoint URL for systemd-journal-upload. This endpoint URL
        includes protocol, upstream address, and port.
      '';
      type = types.str;
      default = "https://${listener.address}:${toString listener.port}";
    };

    tls = {
      caFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "CA bundle used to verify the admin-vm journal receiver certificate.";
      };
      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Client certificate (PEM) used for mTLS to the admin-vm journal receiver.";
      };
      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Client private key (PEM) used for mTLS to the admin-vm journal receiver.";
      };
      minVersion = mkOption {
        type = types.nullOr (
          types.enum [
            "TLS12"
            "TLS13"
          ]
        );
        default = "TLS12";
        description = "Minimum TLS version for the outbound connection.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.tls.certFile != null) && (cfg.tls.keyFile != null);
        message = "Please set ghaf.logging.journalClient.tls.certFile and tls.keyFile.";
      }
    ];

    # Local journal retention
    services.journald =
      (
        if hasStructuredJournald then
          {
            settings.Journal = mkIf config.ghaf.logging.journalRetention.enable (
              {
                MaxRetentionSec = config.ghaf.logging.journalRetention.maxRetention;
                MaxFileSec = config.ghaf.logging.journalRetention.MaxFileSec;
                SyncIntervalSec = config.ghaf.logging.journalRetention.syncInterval;
                SystemMaxUse = config.ghaf.logging.journalRetention.maxDiskUsage;
                SystemMaxFileSize = "100M";
                Storage = "persistent";
              }
              // lib.optionalAttrs config.ghaf.logging.fss.staticSealEnabled { Seal = true; }
            );
          }
        else
          {
            extraConfig = mkIf config.ghaf.logging.journalRetention.enable ''
              MaxRetentionSec=${config.ghaf.logging.journalRetention.maxRetention}
              MaxFileSec=${config.ghaf.logging.journalRetention.MaxFileSec}
              SyncIntervalSec=${config.ghaf.logging.journalRetention.syncInterval}
              SystemMaxUse=${config.ghaf.logging.journalRetention.maxDiskUsage}
              SystemMaxFileSize=100M
              Storage=persistent
              ${optionalString config.ghaf.logging.fss.staticSealEnabled ''
                Seal=yes
              ''}
            '';
          }
      )
      // {
        upload = {
          enable = true;
          settings.Upload = {
            URL = "${cfg.endpoint}";
            ServerKeyFile = cfg.tls.keyFile;
            ServerCertificateFile = cfg.tls.certFile;
            TrustedCertificateFile = cfg.tls.caFile;
          };
        };
      };
    systemd.services.systemd-journal-upload = {
      after = [
        "systemd-journald.service"
        "network-online.target"
        "local-fs.target"
      ]
      ++ lib.optionals givcHostEnabled [ "givc-key-setup.service" ];
      wants = [ "network-online.target" ];
      unitConfig = lib.optionalAttrs needsGivcMount {
        RequiresMountsFor = [ "/etc/givc" ];
      };
      serviceConfig = {
        User = lib.mkForce "root";
        Group = lib.mkForce "root";
      }
      // lib.optionalAttrs (endpointHostPort != null) {
        ExecStartPre = lib.getExe waitForListener;
      };
    };
  };
}
