# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.services.dendrite-pinecone;
  inherit (config.ghaf.reference) services;
  dendrite-pineconePkg = pkgs.callPackage ../../../../packages/dendrite-pinecone/default.nix { };
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  options.ghaf.reference.services.dendrite-pinecone = {
    enable = mkEnableOption "Enable dendrite pinecone module";

    externalNic = mkOption {
      type = types.str;
      default = "";
      description = ''
        External network interface
      '';
    };
    internalNic = mkOption {
      type = types.str;
      default = "";
      description = ''
        Internal network interface
      '';
    };

    serverIpAddr = mkOption {
      type = types.str;
      default = "";
      description = ''
        Dendrite Server Ip address
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.externalNic != "";
        message = "External Nic must be set";
      }
      {
        assertion = cfg.internalNic != "";
        message = "Internal Nic must be set";
      }
      {
        assertion = cfg.serverIpAddr != "";
        message = "Dendrite Pinecone server ip must be set";
      }
    ];

    services.smcroute = {
      enable = true;
      bindingNic = "${cfg.externalNic}";
      rules = ''
        mgroup from ${cfg.externalNic} group ${dendrite-pineconePkg.McastUdpIp}
        mgroup from ${cfg.internalNic} group ${dendrite-pineconePkg.McastUdpIp}
        mroute from ${cfg.externalNic} group ${dendrite-pineconePkg.McastUdpIp} to ${cfg.internalNic}
        mroute from ${cfg.internalNic} group ${dendrite-pineconePkg.McastUdpIp} to ${cfg.externalNic}
      '';
    };
    networking = {
      firewall.enable = true;
      firewall.extraCommands = "

        # TODO: Move all these TcpPort and things like that, to the options of
        #       this module, away from from package itself.

        # Forward incoming TCP traffic on port ${dendrite-pineconePkg.TcpPort} to internal network(comms-vm)
        iptables -t nat -I PREROUTING -i ${cfg.externalNic} -p tcp --dport ${dendrite-pineconePkg.TcpPort} -j DNAT --to-destination  ${cfg.serverIpAddr}:${dendrite-pineconePkg.TcpPort}

        # Enable NAT for outgoing traffic
        iptables -t nat -I POSTROUTING -o ${cfg.externalNic} -p tcp --dport ${dendrite-pineconePkg.TcpPort} -j MASQUERADE

        # Enable NAT for outgoing traffic
        iptables -t nat -I POSTROUTING -o ${cfg.externalNic} -p tcp --sport ${dendrite-pineconePkg.TcpPort} -j MASQUERADE

        # Enable NAT for outgoing udp multicast traffic
        iptables -t nat -I POSTROUTING -o ${cfg.externalNic} -p udp -d ${dendrite-pineconePkg.McastUdpIp} --dport ${dendrite-pineconePkg.McastUdpPort} -j MASQUERADE

        # https://github.com/troglobit/smcroute?tab=readme-ov-file#usage
        iptables -t mangle -I PREROUTING -i ${cfg.externalNic} -d ${dendrite-pineconePkg.McastUdpIp} -j TTL --ttl-set 1
        # ttl value must be set to 1 for avoiding multicast looping
        iptables -t mangle -I PREROUTING -i ${cfg.internalNic} -d ${dendrite-pineconePkg.McastUdpIp} -j TTL --ttl-inc 1

      ";
    };
  };
}
