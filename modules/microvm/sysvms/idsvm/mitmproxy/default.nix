# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.idsvm.mitmproxy;
  inherit (config.ghaf.networking) hosts;
  mitmproxyport = 8080;
  mitmwebUIport = 8081;
in
{
  _file = ./default.nix;

  options.ghaf.virtualization.microvm.idsvm.mitmproxy = {
    enable = lib.mkEnableOption "Whether to enable mitmproxy on ids-vm";
    webUIEnabled = lib.mkOption {
      type = lib.types.bool;
      default =
        config.ghaf.profiles.debug.enable && config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable;
      description = ''
        Whether to enable mitmproxyWebUI on ids-vm
      '';
    };
    webUIPort = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      readOnly = true;
      default = [
        mitmwebUIport
      ];
      description = ''
        MitmwebUI port
      '';
    };
    webUIPswd = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "ghaf";
      description = ''
        MitmwebUI password
      '';
    };
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
          ${pkgs.mitmproxy}/bin/mitmweb --web-host localhost --web-port ${toString mitmwebUIport} --set confdir=/etc/mitmproxy --set web_debug=true --set web_password='${cfg.webUIPswd}'
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

    ghaf.firewall = {

      allowedTCPPorts = [
        mitmproxyport
        mitmwebUIport
      ];

      extra = {

        prerouting.nat = [
          # Redirect http(s) traffic to mitmproxy.
          "-i ${
            hosts.${config.networking.hostName}.interfaceName
          } -p tcp -m multiport --dports 80,443 -j REDIRECT --to-port ${toString mitmproxyport}"
        ]
        ++ lib.optional cfg.webUIEnabled "-p tcp --dport ${toString mitmwebUIport} -j DNAT --to-destination 127.0.0.1:${toString mitmwebUIport}";

        postrouting.nat = lib.optional cfg.webUIEnabled "-m addrtype --src-type LOCAL --dst-type UNICAST -j MASQUERADE";
      };

    };

    environment.systemPackages = [ pkgs.mitmproxy ];

    boot.kernel.sysctl."net.ipv4.conf.all.route_localnet" = cfg.webUIEnabled;

  };
}
