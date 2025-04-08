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
    };

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
