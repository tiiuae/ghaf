# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.host.networking;
in
  with lib; {
    options.ghaf.host.networking = {
      enable = mkEnableOption "Host networking";
      # TODO add options to configure the network, e.g. ip addr etc
    };

    config = mkIf cfg.enable {
      networking = {
        enableIPv6 = false;
        useNetworkd = true;
        interfaces.virbr0.useDHCP = false;
      };

      systemd.network = {
        netdevs."10-virbr0".netdevConfig = {
          Kind = "bridge";
          Name = "virbr0";
          #      MACAddress = "02:00:00:02:02:02";
        };
        networks."10-virbr0" = {
          matchConfig.Name = "virbr0";
          networkConfig.DHCPServer = false;
          addresses = [
            {
              addressConfig.Address = "192.168.101.2/24";
            }
          ];
        };
        # Connect VM tun/tap device to the bridge
        # TODO configure this based on IF the netvm is enabled
        networks."11-netvm" = {
          matchConfig.Name = "tap-*";
          networkConfig.Bridge = "virbr0";
        };
      };
    };
  }
