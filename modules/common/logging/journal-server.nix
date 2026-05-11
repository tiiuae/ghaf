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
    ;
  cfg = config.ghaf.logging.journalServer;
  givcEnabled = config.ghaf.givc.enable;
  givcHostEnabled = config.ghaf.givc.host.enable;
  needsGivcMount = givcEnabled && !givcHostEnabled;
in
{
  _file = ./journal-server.nix;

  options.ghaf.logging.journalServer = {
    enable = mkEnableOption "Logs aggregator server";

    tls = {
      caFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/ca-cert.pem";
        description = "Optional CA bundle for server verification (e.g., /etc/givc/ca-cert.pem). If null, use system CAs.";
      };
      certFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/cert.pem";
        description = "Client certificate (PEM) used for mTLS.";
      };
      keyFile = mkOption {
        type = types.nullOr types.path;
        default = "/etc/givc/key.pem";
        description = "Client private key (PEM) used for mTLS.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.tls.certFile != null) && (cfg.tls.keyFile != null);
        message = "Please set ghaf.logging.journalServer.tls.certFile and tls.keyFile.";
      }
    ];

    services.journald.remote = {
      enable = true;
      inherit (config.ghaf.logging.listener) port;
      settings.Remote = {
        SplitMode = "host";
        OutputDirectory = "/var/log/journal/remote";
        ServerKeyFile = "${cfg.tls.keyFile}";
        ServerCertificateFile = "${cfg.tls.certFile}";
        TrustedCertificateFile = "${cfg.tls.caFile}";
      };
    };

    systemd.services.systemd-journal-remote = {
      after = [
        "systemd-journald.service"
        "local-fs.target"
      ]
      ++ lib.optionals givcHostEnabled [ "givc-key-setup.service" ];
      unitConfig = lib.optionalAttrs needsGivcMount {
        RequiresMountsFor = [ "/etc/givc" ];
      };
      serviceConfig = {
        User = lib.mkForce "root";
        Group = lib.mkForce "root";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/log/journal/remote 2755 root root -"
    ];

    networking.firewall.allowedTCPPorts = [ config.ghaf.logging.listener.port ];

  };
}
