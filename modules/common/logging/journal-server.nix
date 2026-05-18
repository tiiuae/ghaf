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

      terminator = {
        backendPort = mkOption {
          type = types.port;
          default = 3101;
          description = "Local HTTP backend port for systemd-journal-remote when TLS termination is enabled.";
        };
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
        assertion = (!cfg.tls.terminator.verifyClients) || cfg.tls.caFile != null;
        message = "Please set ghaf.logging.journalServer.tls.caFile when mTLS client verification is enabled.";
      }
      {
        assertion = cfg.tls.terminator.backendPort != config.ghaf.logging.listener.port;
        message = "ghaf.logging.journalServer.tls.terminator.backendPort must differ from ghaf.logging.listener.port.";
      }
    ];

    services.journald.remote = {
      enable = true;
      listen = "http";
      port = cfg.tls.terminator.backendPort;
      output = "/var/log/journal/remote/";
      settings.Remote = {
        SplitMode = "host";
      };
    };

    services.stunnel = {
      enable = true;

      servers."ghaf-journal" = {
        accept = config.ghaf.logging.listener.port;
        connect = "127.0.0.1:${toString cfg.tls.terminator.backendPort}";
        cert = cfg.tls.certFile;
        key = cfg.tls.keyFile;
        verify = if cfg.tls.terminator.verifyClients then 2 else 0;
        sslVersionMin = "TLSv1.2";
      }
      // lib.optionalAttrs (cfg.tls.caFile != null) {
        CAfile = cfg.tls.caFile;
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
        Group = lib.mkForce "systemd-journal";
      };
    };

    systemd.sockets.systemd-journal-remote.listenStreams = lib.mkForce [
      ""
      "127.0.0.1:${toString cfg.tls.terminator.backendPort}"
    ];

    systemd.services.stunnel = {
      after = lib.optionals givcHostEnabled [ "givc-key-setup.service" ];
      wants = lib.optionals givcHostEnabled [ "givc-key-setup.service" ];
      unitConfig = lib.optionalAttrs needsGivcMount {
        RequiresMountsFor = [ "/etc/givc" ];
      };
    };

    systemd.tmpfiles.rules = lib.mkAfter [
      "d /var/log/journal/remote 2755 root systemd-journal -"
      "z /var/log/journal/remote 2755 root systemd-journal -"
      "z /var/log/journal/remote/remote-*.journal 0640 root systemd-journal -"
    ];

    networking.firewall.allowedTCPPorts = [ config.ghaf.logging.listener.port ];

  };
}
