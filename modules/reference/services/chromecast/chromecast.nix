# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.chromecast;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  tcpChromeCastPort1 = 8008;
  tcpChromeCastPort2 = 8009;

  ssdpMcastPort = 1900;
  mdnsMcastPort = 5353;
  ssdpMcastIp = "239.255.255.250";
in
{
  _file = ./chromecast.nix;

  options.ghaf.reference.services.chromecast = {
    enable = mkEnableOption "the Chromecast service";

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

    tcpPorts = mkOption {
      type = lib.types.listOf lib.types.port;
      readOnly = true;

      default = [
        tcpChromeCastPort1
        tcpChromeCastPort2
      ];
      description = ''
        Chromecast tcp ports
      '';
    };
    udpPorts = mkOption {
      type = lib.types.listOf lib.types.port;
      readOnly = true;
      default = [
        ssdpMcastPort
        mdnsMcastPort
      ];
      description = ''
        Chromecast udp ports
      '';
    };
    vmName = mkOption {
      type = types.str;
      example = "chrome-vm";
      description = "The name of the chromium/chrome VM to setup chromecast for.";
      default = "chrome-vm";
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
    ];

    # cfg.externalNic comes from (lib.head hardware.definition.network.pciDevices),
    # which enumerates PCI-passthrough NICs and is therefore the Wi-Fi card. A
    # wired uplink arrives via vhotplug at runtime and is not in that list at
    # all, so the multicast routing below is driven by the resolved uplink
    # instead. externalNic survives only as the "what the build assumed" value
    # the resolver compares against, and as the firewall rules' interface until
    # those move too.
    ghaf.networking.uplinkResolver = {
      expectedInterface = lib.mkDefault cfg.externalNic;
      # Both units render the uplink into their configuration at start, so they
      # have to be restarted when it changes, not merely reloaded.
      dependentUnits = [
        "smcroute.service"
        "nw-packet-forwarder.service"
      ];
    };

    services.nw-packet-forwarder = {
      enable = true;
      inherit (cfg) externalNic;
      inherit (cfg) internalNic;
      uplink.enable = true;
      chromecast = {
        enable = true;
        inherit (cfg) vmName;
      };
    };

    services.smcroute = {
      enable = true;
      bindingNic = "${cfg.externalNic}";
      uplink.enable = true;
      # @UPLINK@ is substituted with the resolved interface when the config is
      # generated at start. smcroute asserts at eval time that this placeholder
      # is actually present, so the uplink cannot be silently ignored.
      rules = ''
        mgroup from @UPLINK@ group ${ssdpMcastIp}
        mgroup from ${cfg.internalNic} group ${ssdpMcastIp}
        mroute from @UPLINK@ group ${ssdpMcastIp} to ${cfg.internalNic}
        mroute from ${cfg.internalNic} group ${ssdpMcastIp} to @UPLINK@
      '';
    };

    ghaf.firewall.extra = {

      prerouting.mangle = [
        # TTL adjustments to avoid multicast loops
        "-i ${cfg.externalNic} -d ${ssdpMcastIp} -j TTL --ttl-set 1"
        "-i ${cfg.internalNic} -d ${ssdpMcastIp} -j TTL --ttl-inc 1"
      ];
      forward.filter = [
        # Forward incoming TCP traffic on ports 8008 and 8009 to the internal NIC
        "-i ${cfg.externalNic} -o ${cfg.internalNic} -p tcp --sport ${toString tcpChromeCastPort1} -j ACCEPT"
        "-i ${cfg.externalNic} -o ${cfg.internalNic} -p tcp --sport ${toString tcpChromeCastPort2} -j ACCEPT"
      ];

      postrouting.nat = [
        # Enable NAT for outgoing 8008 and 8009 Chromecast traffic
        "-o ${cfg.externalNic} -p tcp --dport ${toString tcpChromeCastPort1} -j MASQUERADE"
        "-o ${cfg.externalNic} -p tcp --dport ${toString tcpChromeCastPort2} -j MASQUERADE"
        # Enable NAT for outgoing udp multicast traffic
        "-o ${cfg.externalNic} -p udp -d ${ssdpMcastIp} --dport ${toString ssdpMcastPort} -j MASQUERADE"
      ];

    };

  };
}
