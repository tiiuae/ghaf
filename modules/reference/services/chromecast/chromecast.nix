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
  mdnsMcastIp = "224.0.0.251";
in
{
  _file = ./chromecast.nix;

  options.ghaf.reference.services.chromecast = {
    enable = mkEnableOption "the Chromecast service";

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
        assertion = cfg.internalNic != "";
        message = "Internal Nic must be set";
      }
    ];

    # The uplink used to come from (lib.head hardware.definition.network.pciDevices),
    # which enumerates PCI-passthrough NICs and is therefore the Wi-Fi card. A
    # wired uplink arrives via vhotplug at runtime and is not in that list at
    # all, so the multicast routing below is driven entirely by the resolved
    # uplink instead.
    ghaf.networking.uplinkResolver = {
      # Both units render the uplink into their configuration at start, so they
      # have to be restarted when it changes, not merely reloaded.
      dependentUnits = [
        "smcroute.service"
        "nw-packet-forwarder-reconcile.service"
        "ghaf-firewall-uplink.service"
      ];
    };

    services.nw-packet-forwarder = {
      enable = true;
      inherit (cfg) internalNic;
      chromecast = {
        enable = true;
        inherit (cfg) vmName;
      };
    };

    services.smcroute = {
      enable = true;
      # @UPLINK@ is substituted with each resolved uplink in turn, rendering
      # this block once per uplink -- so each gets its own group join and its
      # own route back to chrome-vm.
      #
      # The mDNS mgroup has no matching mroute: nw-pckt-fwd already relays
      # mDNS itself (mdns_enabled is on in the binary), so an mroute here
      # would forward every mDNS packet twice, once via smcrouted's kernel
      # route and once via nw-pckt-fwd's own relay. The join is still needed
      # on its own -- nw-pckt-fwd's raw capture only sees packets once they
      # actually arrive at the interface, and on Wi-Fi an AP doing IGMP
      # snooping will not deliver a multicast group to a station that never
      # joined it, promiscuous mode notwithstanding.
      rules = ''
        mgroup from @UPLINK@ group ${ssdpMcastIp}
        mgroup from @UPLINK@ group ${mdnsMcastIp}
        mroute from @UPLINK@ group ${ssdpMcastIp} to ${cfg.internalNic}
      '';
      # The other direction fans out from chrome-vm to every uplink on one
      # line -- an mroute's `to` list takes multiple interfaces, and
      # declaring it once per uplink like `rules` above would instead
      # redeclare the same (from ethint0, group) route with a different
      # destination each time, which smcrouted rejects as a duplicate.
      rulesOnce = ''
        mgroup from ${cfg.internalNic} group ${ssdpMcastIp}
        mroute from ${cfg.internalNic} group ${ssdpMcastIp} to @UPLINKS@
      '';
    };

    # Rules that name the uplink go into ghaf.firewall.uplink.rules rather than
    # ghaf.firewall.extra: extra.* is rendered at build time and so can only
    # name an interface known then, which for a wired device is the wrong one.
    # These are applied with @UPLINK@ substituted, and withdrawn when there is
    # no uplink. Rules touching only the internal NIC stay in extra.*, since
    # ethint0 is static.
    ghaf.firewall = {
      uplink = {
        enable = true;

        rules.prerouting.mangle = [
          # TTL adjustments to avoid multicast loops
          "-i @UPLINK@ -d ${ssdpMcastIp} -j TTL --ttl-set 1"
        ];
        rules.forward.filter = [
          # Forward incoming TCP traffic on ports 8008 and 8009 to the internal NIC
          "-i @UPLINK@ -o ${cfg.internalNic} -p tcp --sport ${toString tcpChromeCastPort1} -j ACCEPT"
          "-i @UPLINK@ -o ${cfg.internalNic} -p tcp --sport ${toString tcpChromeCastPort2} -j ACCEPT"
        ];
        rules.postrouting.nat = [
          # Enable NAT for outgoing 8008 and 8009 Chromecast traffic
          "-o @UPLINK@ -p tcp --dport ${toString tcpChromeCastPort1} -j MASQUERADE"
          "-o @UPLINK@ -p tcp --dport ${toString tcpChromeCastPort2} -j MASQUERADE"
          # Enable NAT for outgoing udp multicast traffic
          "-o @UPLINK@ -p udp -d ${ssdpMcastIp} --dport ${toString ssdpMcastPort} -j MASQUERADE"
        ];
      };

      extra.prerouting.mangle = [
        "-i ${cfg.internalNic} -d ${ssdpMcastIp} -j TTL --ttl-inc 1"
      ];
    };

  };
}
