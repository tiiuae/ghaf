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
    enable = mkEnableOption "the dendrite pinecone module";

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
      # externalNic is no longer required: the interface is resolved at runtime.
      {
        assertion = cfg.internalNic != "";
        message = "Internal Nic must be set";
      }
      {
        assertion = cfg.serverIpAddr != "";
        message = "Dendrite Pinecone server ip must be set";
      }
    ];

    # Same treatment as chromecast: the LAN-facing interface is resolved at
    # runtime, so @UPLINK@ stands in for it wherever it appears and is
    # substituted when the configuration is applied. Rules naming only the
    # internal NIC stay static, since ethint0 does not move.
    #
    # Note this service is currently enabled on no target at all, so unlike
    # chromecast the change here is unexercised. It is made anyway because
    # leaving one consumer on the old build-time NIC would quietly reintroduce
    # the bug the moment someone switched it on.
    services.smcroute = {
      enable = true;
      uplink.enable = true;
      rules = ''
        mgroup from @UPLINK@ group ${cfg.McastUdpIp}
        mgroup from ${cfg.internalNic} group ${cfg.McastUdpIp}
        mroute from @UPLINK@ group ${cfg.McastUdpIp} to ${cfg.internalNic}
        mroute from ${cfg.internalNic} group ${cfg.McastUdpIp} to @UPLINK@
      '';
    };

    ghaf.networking.uplinkResolver.dependentUnits = [
      "smcroute.service"
      "ghaf-firewall-uplink.service"
    ];

    ghaf.firewall = {
      uplink = {
        enable = true;
        # TODO: Move all these TcpPort and things like that, to the options of
        #       this module, away from from package itself.
        rules.prerouting.nat = [
          # Forward incoming TCP traffic on port ${cfg.TcpPort} to internal network(comms-vm)
          "-i @UPLINK@ -p tcp --dport ${cfg.TcpPort} -j DNAT --to-destination  ${cfg.serverIpAddr}:${cfg.TcpPort}"
        ];
        rules.prerouting.mangle = [
          # https://github.com/troglobit/smcroute?tab=readme-ov-file#usage
          "-i @UPLINK@ -d ${cfg.McastUdpIp} -j TTL --ttl-set 1"
        ];
        rules.postrouting.nat = [
          # Enable NAT for outgoing traffic
          "-o @UPLINK@ -p tcp --dport ${cfg.TcpPort} -j MASQUERADE"
          # Enable NAT for outgoing traffic
          "-o @UPLINK@ -p tcp --sport ${cfg.TcpPort} -j MASQUERADE"
          # Enable NAT for outgoing udp multicast traffic
          "-o @UPLINK@ -p udp -d ${cfg.McastUdpIp} --dport ${cfg.McastUdpPort} -j MASQUERADE"
        ];
      };

      extra.prerouting.mangle = [
        # ttl value must be set to 1 for avoiding multicast looping
        "-i ${cfg.internalNic} -d ${cfg.McastUdpIp} -j TTL --ttl-inc 1"
      ];
    };
  };
}
