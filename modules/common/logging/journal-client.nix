# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
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
in
{
  _file = ./journal-client.nix;

  options.ghaf.logging.journalClient = {
    enable = mkEnableOption "Journal uploader client service";
    endpoint = mkOption {
      description = ''
        Assign endpoint url value to the alloy.service running in
        different log producers. This endpoint URL will include
        protocol, upstream, address along with port value.
      '';
      type = types.str;
      default = "https://${listener.address}:${toString listener.port}";
    };

    tls = {
      caFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "CA bundle used to verify the admin-vm TLS terminator certificate.";
      };
      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Client certificate (PEM) used for mTLS to the admin-vm.";
      };
      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Client private key (PEM) used for mTLS to the admin-vm.";
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
    services.journald = {
      extraConfig = mkIf config.ghaf.logging.journalRetention.enable ''
        MaxRetentionSec=${config.ghaf.logging.journalRetention.maxRetention}
        MaxFileSec=${config.ghaf.logging.journalRetention.MaxFileSec}
        SystemMaxUse=${config.ghaf.logging.journalRetention.maxDiskUsage}
        SystemMaxFileSize=100M
        Storage=persistent
        ${optionalString config.ghaf.logging.fss.enable ''
          Seal=yes
        ''}
      '';
    };

    services.journald.upload = {
      enable = true;
      settings.Upload = {
        URL = "${cfg.endpoint}";
        ServerKeyFile = cfg.tls.keyFile;
        ServerCertificateFile = cfg.tls.certFile;
        TrustedCertificateFile = cfg.tls.caFile;
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
      };
    };
  };
}
