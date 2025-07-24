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
    mkEnableOption
    mkDefault
    mkIf
    optionals
    mkOption
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
      type = lib.types.str;
      default = "virbr0";
    };
  };

  config = mkIf cfg.enable {

    networking = {
      enableIPv6 = false;
      useNetworkd = true;
      interfaces."${cfg.bridgeNicName}".useDHCP = false;
      hostName = "ghaf-host";
      firewall.enable = mkDefault false;
    };
    # ip forwarding functionality is needed for iptables
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # https://github.com/NixOS/nixpkgs/issues/111852
    ghaf.firewall.extra.forward.filter = lib.mkIf config.virtualisation.docker.enable [
      "-i ${cfg.bridgeNicName} -o ${cfg.bridgeNicName} -j ACCEPT"
    ];

    # TODO Remove host networking
    systemd.network = {
      netdevs."10-${cfg.bridgeNicName}".netdevConfig = {
        Kind = "bridge";
        Name = "${cfg.bridgeNicName}";
        #      MACAddress = "02:00:00:02:02:02";
      };
      networks."10-${cfg.bridgeNicName}" = {
        matchConfig.Name = "${cfg.bridgeNicName}";
        networkConfig.DHCPServer = false;
        addresses = [
          { Address = "${hosts.${hostName}.ipv4}/${toString hosts.${hostName}.ipv4SubnetPrefixLength}"; }
        ];
        gateway = optionals (builtins.hasAttr "net-vm" config.microvm.vms) [ "${hosts."net-vm".ipv4}" ];
      };
      # Connect VM tun/tap device to the bridge
      # TODO configure this based on IF the netvm is enabled
      networks."11-netvm" = {
        matchConfig.Name = "tap-*";
        networkConfig.Bridge = "${cfg.bridgeNicName}";
      };
    };

    environment.etc = {
      ${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;
    };

    services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;
  };
}
