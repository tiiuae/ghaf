# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.host.networking;
  inherit (lib)
    concatStringsSep
    hasAttr
    mapAttrsToList
    mkEnableOption
    mkDefault
    mkIf
    mkOption
    mkMerge
    optionalAttrs
    optionals
    types
    ;
  sshKeysHelper = pkgs.callPackage ../common/ssh-keys-helper.nix { inherit config; };
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
in
{
  options.ghaf.host.networking = {
    enable = mkEnableOption "Host networking";
    bridgeNicName = mkOption {
      description = "Name of the internal interface";
      type = types.str;
      default = "virbr0";
    };
  };

  config = mkMerge [

    # Common networking configuration that sets up a bridge network for VMs
    {
      networking = {
        hostName = "ghaf-host";
        enableIPv6 = false;
        useNetworkd = true;
        interfaces."${cfg.bridgeNicName}".useDHCP = false;
        firewall.enable = mkDefault false;
      };

      # ip forwarding functionality is needed for iptables
      boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

      # https://github.com/NixOS/nixpkgs/issues/111852
      ghaf.firewall.extra.forward.filter = lib.mkIf config.virtualisation.docker.enable [
        "-i ${cfg.bridgeNicName} -o ${cfg.bridgeNicName} -j ACCEPT"
      ];

      systemd.network = {
        netdevs."10-${cfg.bridgeNicName}".netdevConfig = {
          Kind = "bridge";
          Name = "${cfg.bridgeNicName}";
        };

        networks."10-${cfg.bridgeNicName}" = {
          matchConfig.Name = "${cfg.bridgeNicName}";
          networkConfig = {
            DHCP = false;
            DHCPServer = false;
          };
          linkConfig = {
            ARP = false;
          };
          addresses = [
            { Address = "${hosts.${hostName}.ipv4}/${toString hosts.${hostName}.ipv4SubnetPrefixLength}"; }
          ];
          gateway = optionals (hasAttr "net-vm" config.microvm.vms) [ "${hosts."net-vm".ipv4}" ];
        };

        # Connect VM tun/tap device to the bridge
        networks."11-netvm" = optionalAttrs (hasAttr "net-vm" config.microvm.vms) {
          matchConfig.Name = "tap-*";
          networkConfig.Bridge = "${cfg.bridgeNicName}";
        };
      };

      # Enforce static ARP with ebtables
      ghaf.networking.static-arp.enable = true;
    }

    # Host networking configuration, sets up a veth pair and connects it to the bridge
    (mkIf cfg.enable {

      networking = {
        firewall.allowedTCPPorts = [ 22 ];
        firewall.allowedUDPPorts = [ 67 ];
        nat = {
          enable = true;
          internalInterfaces = [ hosts.${hostName}.interfaceName ];
        };
        interfaces.${hosts.${hostName}.interfaceName}.useDHCP = false;
      };

      systemd.network = {
        netdevs."20-host-veth" = {
          netdevConfig = {
            Name = hosts.${hostName}.interfaceName;
            Kind = "veth";
            MACAddress = hosts.${hostName}.mac;
          };
          # Not technically a tap device, but part of veth pair
          peerConfig.Name = "tap-${hostName}";
        };
        networks."20-${hosts.${hostName}.interfaceName}" = {
          matchConfig.Name = "${hosts.${hostName}.interfaceName}";
          addresses = [ { Address = "${hosts.${hostName}.ipv4}/24"; } ];
          gateway = optionals (builtins.hasAttr "net-vm" config.microvm.vms) [ "${hosts."net-vm".ipv4}" ];
          linkConfig = {
            RequiredForOnline = "routable";
            ActivationPolicy = "always-up";
          };
          extraConfig = concatStringsSep "\n" (
            mapAttrsToList (_: entry: ''
              [Neighbor]
              Address=${entry.ipv4}
              LinkLayerAddress=${entry.mac}
            '') hosts
          );
        };
      };

      services.resolved.dnssec = "false";

      environment.etc = {
        ${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;
      };
      services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;
    })
  ];
}
