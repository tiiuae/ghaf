# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.vm-networking;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    hasAttr
    ;
  inherit (config.ghaf.networking) hosts;

  isIdsvmEnabled = hasAttr "ids-vm" hosts;
  netVmAddress = hosts."net-vm".ipv4;
  idsVmAddress = hosts."ids-vm".ipv4;
  gateway = if isIdsvmEnabled && (cfg.vmName != "ids-vm") then [ idsVmAddress ] else [ netVmAddress ];
in
{
  options.ghaf.virtualization.microvm.vm-networking = {
    enable = mkEnableOption "Enable vm networking configuration";
    isGateway = mkEnableOption "Enable gateway configuration";
    vmName = mkOption {
      description = "Name of the VM";
      type = types.nullOr types.str;
    };
    interfaceName = mkOption {
      description = "Name of the internal interface";
      type = types.str;
      default = "ethint0";
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.vmName != null;
        message = "Missing VM name, try setting the option";
      }
    ];

    networking = {
      hostName = cfg.vmName;
      enableIPv6 = false;
      useNetworkd = true;
      nat = {
        enable = true;
        internalInterfaces = [ cfg.interfaceName ];
      };

      firewall = {
        rejectPackets = true;
        checkReversePath = "loose";
        logReversePathDrops = true;
        allowPing = false; # ping rule is added manually with extraCommands
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ 67 ];
        extraPackages = [
          pkgs.ipset
          pkgs.coreutils
          pkgs.gawk
        ];
        extraCommands = lib.mkBefore ''
            # Set the default policies
            iptables -P INPUT DROP
            iptables -P FORWARD DROP
            iptables -P OUTPUT ACCEPT

            # delete ctstate RELATED,ESTABLISHED and lo rules 
            iptables -D nixos-fw -i lo -j nixos-fw-accept
            iptables -D nixos-fw -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept

            
            iptables -N ghaf-fw-in-filter
            iptables -I INPUT -j ghaf-fw-in-filter

            
            iptables -A ghaf-fw-in-filter -i lo -j ACCEPT
            iptables -A ghaf-fw-in-filter -p icmp --icmp-type echo-request -m limit --limit 1/minute --limit-burst 5 -j ACCEPT
            iptables -A ghaf-fw-in-filter -p icmp --icmp-type echo-request -j DROP
            iptables -A ghaf-fw-in-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            
            iptables -I OUTPUT -o lo -j ACCEPT  

          ### PREROUTING rules ###
          iptables -t mangle -N ghaf-fw-pre-mangle
          iptables -t mangle -I PREROUTING -j ghaf-fw-pre-mangle

          # Drop invalid packets
          iptables -t mangle -A ghaf-fw-pre-mangle -m conntrack --ctstate INVALID -j DROP
          # Block packets with bogus TCP flags  
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags SYN,RST SYN,RST -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,RST FIN,RST -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,ACK FIN -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,URG URG -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,FIN FIN -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,PSH PSH -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL ALL -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL NONE -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j DROP 
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j DROP  

          ### INPUT rules ###
          iptables -F nixos-fw-accept 2> /dev/null || true
          iptables -A nixos-fw-accept -p tcp --syn -m conntrack --ctstate NEW -j ACCEPT
          iptables -A nixos-fw-accept -p udp -m conntrack --ctstate NEW  -j ACCEPT
          iptables -A nixos-fw-accept -j nixos-fw-log-refuse

        '';
      };

    };

    microvm.interfaces = [
      {
        type = "tap";
        # The interface names must have maximum length of 15 characters
        id = "tap-${cfg.vmName}";
        inherit (hosts.${cfg.vmName}) mac;
      }
    ];

    systemd.network = {
      enable = true;
      # Set internal network's interface name
      links."10-${cfg.interfaceName}" = {
        matchConfig.PermanentMACAddress = hosts.${cfg.vmName}.mac;
        linkConfig.Name = cfg.interfaceName;
      };
      networks."10-${cfg.interfaceName}" = {
        matchConfig.MACAddress = hosts.${cfg.vmName}.mac;
        addresses = [ { Address = "${hosts.${cfg.vmName}.ipv4}/24"; } ];
        linkConfig.RequiredForOnline = "routable";
        linkConfig.ActivationPolicy = "always-up";
      }
      // lib.optionalAttrs ((!cfg.isGateway) || (cfg.vmName == "ids-vm")) { inherit gateway; };
    };

    # systemd-resolved does not support local names resolution
    # without configuring a local domain. With the local domain,
    # one would need also to disable DNSSEC for the clients.
    # Disabling DNSSEC for other VM then NetVM is
    # completely safe since they use NetVM as DNS proxy.
    services.resolved.dnssec = "false";
  };
}
