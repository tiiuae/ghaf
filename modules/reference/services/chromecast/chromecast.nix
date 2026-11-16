# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.ghaf.reference.services.google-chromecast;
  inherit (lib) mkIf;
  tcpChromeCastPort1 = 8008;
  tcpChromeCastPort2 = 8009;

  ssdpMcastPort = 1900;
  mdnsMcastPort = 5353;
  ssdpMcastIp = "239.255.255.250";
  mdnsMcastIp = "224.0.0.251";

  # Only the host has vmConfig; the cast VM imports this file too.
  isHost = lib.hasAttrByPath [ "ghaf" "virtualization" "vmConfig" ] options;
  senders = lib.attrNames (
    lib.filterAttrs (
      _: vm: (lib.ghaf.vm.getConfig vm).ghaf.reference.services.google-chromecast.enable or false
    ) (config.microvm.vms or { })
  );
  vmName = lib.head senders;

  # A receiver picks its streaming port at run time, so admit the hosts the
  # cast channel went to instead of a port, until it has been quiet a minute.
  castRules = match: [
    "${match}-p tcp --dport ${toString tcpChromeCastPort2} -m recent --name cast --rdest --set"
    "${match}-p udp -m recent --name cast --rdest --rcheck --seconds 60 --reap -j ACCEPT"
  ];

  netVmModule =
    { config, ... }:
    let
      internalNic = config.ghaf.networking.hosts.${config.networking.hostName}.interfaceName;
      ipt = config.ghaf.firewall.cmd;
      fwdChain = "${config.ghaf.firewall.chainNamePrefix}dyn-filter-fwd";
      castVmIp = config.ghaf.networking.hosts.${vmName}.ipv4;
    in
    {
      imports = [
        ../nw-packet-forwarder/nw-packet-forwarder.nix
        ../smcroute/smcroute.nix
      ];

      # Multicast routing below follows the resolved uplink rather than the old
      # build-time PCI-passthrough NIC guess, which a wired dock never matched.
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
        inherit internalNic;
        chromecast = {
          enable = true;
          inherit vmName;
        };
      };

      services.smcroute = {
        enable = true;
        rules = {
          # No mroute for mDNS: nw-pckt-fwd already relays it, so one here would
          # double-forward. The mgroup join is still needed -- an IGMP-snooping AP
          # won't deliver the group to a station that never joined it.
          perUplink = ''
            mgroup from @UPLINK@ group ${ssdpMcastIp}
            mgroup from @UPLINK@ group ${mdnsMcastIp}
            mroute from @UPLINK@ group ${ssdpMcastIp} to ${internalNic}
          '';
          once = ''
            mgroup from ${internalNic} group ${ssdpMcastIp}
            mroute from ${internalNic} group ${ssdpMcastIp} to @UPLINKS@
          '';
        };
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
            "-i @UPLINK@ -o ${internalNic} -p tcp --sport ${toString tcpChromeCastPort1} -j ACCEPT"
            "-i @UPLINK@ -o ${internalNic} -p tcp --sport ${toString tcpChromeCastPort2} -j ACCEPT"
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
          "-i ${internalNic} -d ${ssdpMcastIp} -j TTL --ttl-inc 1"
        ];

        dynamicChains.enable = true;
      };

      # The dynamic chain is kept across reloads, so add each rule once.
      networking.firewall.extraCommands = lib.mkAfter (
        lib.concatMapStrings (rule: ''
          ${ipt} -C ${fwdChain} ${rule} 2>/dev/null || ${ipt} -A ${fwdChain} ${rule}
        '') (castRules "-i ${internalNic} ! -o ${internalNic} -s ${castVmIp} ")
      );
    };

in
{
  _file = ./chromecast.nix;

  options.ghaf.reference.services.google-chromecast.enable = lib.mkEnableOption "Chromecast service";

  config =
    if isHost then
      mkIf (config.ghaf.reference.services.enable && cfg.enable) {
        assertions = [
          {
            # nw-packet-forwarder relays for a single VM.
            assertion = lib.length senders == 1;
            message = "Chromecast needs exactly one VM with google-chromecast enabled, found: ${toString senders}";
          }
        ];
        ghaf.virtualization.vmConfig.sysvms.netvm.extraModules = [ netVmModule ];
      }
    else
      mkIf cfg.enable {
        ghaf.firewall = {
          allowedUDPPorts = [
            ssdpMcastPort
            mdnsMcastPort
          ];
          allowedTCPPorts = [
            tcpChromeCastPort1
            tcpChromeCastPort2
          ]
          ++
            map
              (port: {
                inherit port;
                direction = "output";
              })
              [
                tcpChromeCastPort1
                tcpChromeCastPort2
              ];
          extra.output.filter = castRules "";
        };
      };
}
