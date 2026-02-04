# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.dendrite-pinecone;
  #TODO: this seems to be unused check later
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./dendrite-pinecone.nix;

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

    TcpPort = mkOption {
      type = types.str;
      default = "49000";
      description = ''
        TCP port for dendrite pinecone
      '';
    };
    McastUdpPort = mkOption {
      type = types.str;
      default = "60606";
      description = ''
        Multicast UDP port for dendrite pinecone
      '';
    };

    McastUdpIp = mkOption {
      type = types.str;
      default = "239.0.0.114";
      description = ''
        Multicast UDP IP for dendrite pinecone
      '';
    };

    TcpPortInt = mkOption {
      type = types.int;
      default = 49000;
      description = ''
        TCP port for dendrite pinecone
      '';
    };

    McastUdpPortInt = mkOption {
      type = types.int;
      default = 60606;
      description = ''
        Multicast UDP port for dendrite pinecone
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
        mgroup from ${cfg.externalNic} group ${cfg.McastUdpIp}
        mgroup from ${cfg.internalNic} group ${cfg.McastUdpIp}
        mroute from ${cfg.externalNic} group ${cfg.McastUdpIp} to ${cfg.internalNic}
        mroute from ${cfg.internalNic} group ${cfg.McastUdpIp} to ${cfg.externalNic}
      '';
    };

    ghaf.firewall.extra = {
      # TODO: Move all these TcpPort and things like that, to the options of
      #       this module, away from from package itself.
      prerouting = {
        nat = [
          # Forward incoming TCP traffic on port ${cfg.TcpPort} to internal network(comms-vm)
          "-i ${cfg.externalNic} -p tcp --dport ${cfg.TcpPort} -j DNAT --to-destination  ${cfg.serverIpAddr}:${cfg.TcpPort}"
        ];
        mangle = [
          # https://github.com/troglobit/smcroute?tab=readme-ov-file#usage
          "-i ${cfg.externalNic} -d ${cfg.McastUdpIp} -j TTL --ttl-set 1"
          # ttl value must be set to 1 for avoiding multicast looping
          "-i ${cfg.internalNic} -d ${cfg.McastUdpIp} -j TTL --ttl-inc 1"
        ];
      };

      postrouting = {
        nat = [
          # Enable NAT for outgoing traffic
          "-o ${cfg.externalNic} -p tcp --dport ${cfg.TcpPort} -j MASQUERADE"
          # Enable NAT for outgoing traffic
          "-o ${cfg.externalNic} -p tcp --sport ${cfg.TcpPort} -j MASQUERADE"
          # Enable NAT for outgoing udp multicast traffic
          "-o ${cfg.externalNic} -p udp -d ${cfg.McastUdpIp} --dport ${cfg.McastUdpPort} -j MASQUERADE"
        ];
      };

    };
  };
}
