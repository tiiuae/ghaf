# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  networking = {
    enableIPv6 = false;
    firewall.allowedUDPPorts = [67]; # DHCP
    useNetworkd = true;
  };
  systemd.network = {
    netdevs = {
      "virbr0".netdevConfig = {
        Kind = "bridge";
        Name = "virbr0";
      };
      "virbr1".netdevConfig = {
        Kind = "bridge";
        Name = "virbr1";
      };
    };
    networks = {
      "virbr0" = {
        matchConfig.Name = "virbr0";
        networkConfig.DHCPServer = true;
        addresses = [
          {
            addressConfig.Address = "192.168.100.1/24";
          }
        ];
      };
      "virbr1" = {
        matchConfig.Name = "virbr1";
        networkConfig.DHCPServer = true;
        addresses = [
          {
            addressConfig.Address = "192.168.200.1/24";
          }
        ];
      };
    };
    # Connect VM tun/tap device to the bridge
    networks."11-netvm" = {
      matchConfig.Name = "vm-netvm";
      networkConfig.Bridge = "virbr0";
    };
    networks."11-guivm" = {
      matchConfig.Name = "vm-guivm";
      networkConfig.Bridge = "virbr1";
    };
  };
}
