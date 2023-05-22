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
        };
        networks."10-virbr0" = {
          matchConfig.Name = "virbr0";
          networkConfig.DHCPServer = false;
          addresses = [
            {
              # Set address for debugging access
              addressConfig.Address = "192.168.110.2/24";
            }
          ];
        };

        netdevs."10-virbr1".netdevConfig = {
          Kind = "bridge";
          Name = "virbr1";
        };
        networks."10-virbr1" = {
          matchConfig.Name = "virbr1";
          networkConfig.DHCPServer = false;
          addresses = [
            {
              # Set address for debbugging access
              addressConfig.Address = "192.168.111.2/24";
            }
          ];
        };

        # Connect VM tun/tap devices to the bridges
        networks."11-netvm" = {
          matchConfig.Name = "vmbr0-*";
          networkConfig.Bridge = "virbr0";
        };

        networks."11-idsvm" = {
          matchConfig.Name = "vmbr1-*";
          networkConfig.Bridge = "virbr1";
        };
      };
    };
  }
