# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.services.firewall;
in
{
  options.ghaf.reference.services.firewall = {
    enable = lib.mkEnableOption "Ghaf reference firewall for virtual machines";

    # WARN: if all the traffic including VPN flowing through proxy is intended,
    # remove "151.253.154.18" rule and pass "--proxy-server=http://192.168.100.1:3128" to openconnect(VPN) app.
    # also remove "151.253.154.18,tii.ae,.tii.ae,sapsf.com,.sapsf.com" addresses from noProxy option and add
    # them to allow acl list in modules/reference/appvms/3proxy-config.nix file.
    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "151.253.154.18" ];
      description = "List of IP addresses allowed through the firewall";
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      firewall = {
        enable = true;
        extraCommands =
          let
            allowRules = lib.concatStringsSep "\n" (
              map (ip: ''
                iptables -I OUTPUT -p tcp -d ${ip} --dport 80 -j ACCEPT
                iptables -I OUTPUT -p tcp -d ${ip} --dport 443 -j ACCEPT
                iptables -I INPUT -p tcp -s ${ip} --sport 80 -j ACCEPT
                iptables -I INPUT -p tcp -s ${ip} --sport 443 -j ACCEPT
              '') cfg.allowedIPs
            );
          in
          ''
            # Default policy
            iptables -P INPUT DROP

            iptables -A INPUT -i lo -j ACCEPT
            iptables -A OUTPUT -o lo -j ACCEPT

            # Block any other unwanted traffic (optional)
            iptables -N logreject
            iptables -A logreject -j LOG
            iptables -A logreject -j REJECT

            # allow everything for local VPN traffic
            iptables -A INPUT -i tun0 -j ACCEPT
            iptables -A FORWARD -i tun0 -j ACCEPT
            iptables -A FORWARD -o tun0 -j ACCEPT
            iptables -A OUTPUT -o tun0 -j ACCEPT

            ${allowRules}

            # Block all other HTTP and HTTPS traffic
            iptables -A OUTPUT -p tcp --dport 80 -j logreject
            iptables -A OUTPUT -p tcp --dport 443 -j logreject
            iptables -A OUTPUT -p udp --dport 80 -j logreject
            iptables -A OUTPUT -p udp --dport 443 -j logreject

          '';
      };
    };
  };
}
