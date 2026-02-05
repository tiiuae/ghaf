# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.host.networking;
  inherit (lib)
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkDefault
    mkIf
    mkMerge
    mkOption
    optionalAttrs
    optionals
    types
    ;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
  inherit (config.ghaf.common.extraNetworking) enableStaticArp;
  hasNetvm = lib.hasAttr "net-vm" config.microvm.vms;
in
{
  _file = ./networking.nix;

  options.ghaf.host.networking = {
    enable = mkEnableOption "Host networking";
    enableExternalNetworking = mkOption {
      description = ''
        Enable external host networking support. This option currently enables the host nat,
        and disables the default configuration of deactivating any additional interfaces. Note
        that even with this configuration, the host networking can be enabled manually if needed.
        By default, this option is enabled if no net-vm is defined, or the debug profile is enabled.
      '';
      type = types.bool;
      default = (!hasNetvm) || config.ghaf.profiles.debug.enable;
      defaultText = literalExpression ''
        (!(hasAttr "net-vm" config.microvm.vms)) || config.ghaf.profiles.debug.enable
      '';
    };
    bridgeNicName = mkOption {
      description = "Name of the internal interface";
      type = types.str;
      default = "virbr0";
    };
  };

  config = mkMerge [

    # Common networking configuration that sets up a network bridge for VMs
    {
      # To disable the filtering of VM network packets through the firewall.
      boot = {
        blacklistedKernelModules = [ "br_netfilter" ];

        kernel.sysctl = {
          # ip forwarding functionality is needed for iptables
          "net.ipv4.ip_forward" = 1;
          # reply only if the target IP address is local address configured on the incoming interface
          "net.ipv4.conf.all.arp_ignore" = 1;
        };
      };

      # Enable ARP filtering with ebtables
      ghaf.firewall.filter-arp = enableStaticArp;

      # Setup host VM network bridge
      systemd.network = {
        netdevs."10-${cfg.bridgeNicName}".netdevConfig = {
          Kind = "bridge";
          Name = "${cfg.bridgeNicName}";
          MACAddress = hosts.${hostName}.mac;
        };
        networks = {
          "10-${cfg.bridgeNicName}" = {
            matchConfig.Name = "${cfg.bridgeNicName}";
            networkConfig = {
              LinkLocalAddressing = "no";
            };
            linkConfig = {
              RequiredForOnline = "routable";
              ActivationPolicy = "always-up";
              ARP = !enableStaticArp;
            };
          };
          # Connect VM tun/tap device to the bridge
          "11-vm-network" = {
            matchConfig.Name = "tap-*";
            networkConfig.Bridge = "${cfg.bridgeNicName}";
          };
          # Disable addititional, non-defined external interfaces
          "99-disable-external" = optionalAttrs (!cfg.enableExternalNetworking) {
            matchConfig.Name = [
              "en*"
              "eth*"
              "wl*"
              "ww*"
            ];
            linkConfig.ActivationPolicy = "down";
          };
        };
      };
    }

    # Host networking configuration
    (mkIf cfg.enable {

      # Enable dynamic hostname generation on host
      ghaf.identity.dynamicHostName.enable = true;

      networking = {
        hostName = "ghaf-host";
        enableIPv6 = false;
        useNetworkd = true;
        nat = {
          enable = cfg.enableExternalNetworking;
          internalInterfaces = [ cfg.bridgeNicName ];
        };
        firewall.enable = mkDefault false;
      };

      ghaf.firewall = {
        allowedTCPPorts = optionals config.ghaf.development.ssh.daemon.enable [ 22 ];
        allowedUDPPorts = optionals (!hasNetvm) [ 67 ];
      };

      boot.kernel.sysctl = optionalAttrs enableStaticArp {
        # only reply on same interface
        "net.ipv4.conf.${cfg.bridgeNicName}.arp_filter" = 1;
        # do not create new entries in the ARP table
        "net.ipv4.conf.${cfg.bridgeNicName}.arp_accept" = 0;
        # uses the best local IP on the outgoing interface
        "net.ipv4.conf.${cfg.bridgeNicName}.arp_announce" = 2;
        # no reply to ARP requests
        "net.ipv4.conf.${cfg.bridgeNicName}.arp_ignore" = 8;
      };

      systemd.network = {
        networks."10-${cfg.bridgeNicName}" = {
          matchConfig.Name = "${cfg.bridgeNicName}";
          addresses = [
            { Address = "${hosts.${hostName}.ipv4}/${toString hosts.${hostName}.ipv4SubnetPrefixLength}"; }
          ];
          gateway = optionals hasNetvm [ "${hosts."net-vm".ipv4}" ];
          networkConfig = {
            DHCP = hasNetvm && !enableStaticArp;
            DHCPServer = !hasNetvm && !enableStaticArp;
          };
          extraConfig = lib.concatStringsSep "\n" (
            mapAttrsToList (_: entry: ''
              [Neighbor]
              Address=${entry.ipv4}
              LinkLayerAddress=${entry.mac}
            '') hosts
          );
        };
      };
    })
  ];
}
