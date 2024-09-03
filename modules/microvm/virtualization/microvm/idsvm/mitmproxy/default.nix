# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.idsvm.mitmproxy;
  mitmproxyport = 8080;
  mitmwebUIport = 8081;
in
{
  options.ghaf.virtualization.microvm.idsvm.mitmproxy = {
    enable = lib.mkEnableOption "Whether to enable mitmproxy on ids-vm";
  };

  config = lib.mkIf cfg.enable {
    # Here we add default CA keypair and corresponding self-signed certificate
    # for mitmproxy in different formats. These should be, of course, randomly and
    # securely generated and stored for each instance, but for development purposes
    # we use these fixed ones.
    environment.etc = {
      "mitmproxy/mitmproxy-ca-cert.cer".source = ./mitmproxy-ca/mitmproxy-ca-cert.cer;
      "mitmproxy/mitmproxy-ca-cert.p12".source = ./mitmproxy-ca/mitmproxy-ca-cert.p12;
      "mitmproxy/mitmproxy-ca-cert.pem".source = ./mitmproxy-ca/mitmproxy-ca-cert.pem;
      "mitmproxy/mitmproxy-ca.pem".source = ./mitmproxy-ca/mitmproxy-ca.pem;
      "mitmproxy/mitmproxy-ca.p12".source = ./mitmproxy-ca/mitmproxy-ca.p12;
      "mitmproxy/mitmproxy-dhparam.pem".source = ./mitmproxy-ca/mitmproxy-dhparam.pem;
    };

    systemd.services."mitmweb-server" =
      let
        mitmwebScript = pkgs.writeShellScriptBin "mitmweb-server" ''
          ${pkgs.mitmproxy}/bin/mitmweb --web-host localhost --web-port ${toString mitmwebUIport} --set confdir=/etc/mitmproxy
        '';
      in
      {
        enable = true;
        description = "Run mitmweb to establish web interface for mitmproxy";
        path = [ mitmwebScript ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${mitmwebScript}/bin/mitmweb-server";
          Restart = "on-failure";
          RestartSec = "1";
        };
      };

    networking = {
      firewall.allowedTCPPorts = [
        mitmproxyport
        mitmwebUIport
      ];
      nat.extraCommands =
        # Redirect http(s) traffic to mitmproxy.
        ''
          iptables -t nat -A PREROUTING -i ethint0 -p tcp --dport 80 -j REDIRECT --to-port ${toString mitmproxyport}
          iptables -t nat -A PREROUTING -i ethint0 -p tcp --dport 443 -j REDIRECT --to-port ${toString mitmproxyport}
        '';
    };
    environment.systemPackages = [ pkgs.mitmproxy ];
  };
}
