# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  networking = {
    enableIPv6 = false;
    firewall.allowedUDPPorts = [67]; # DHCP
    useNetworkd = true;
  };

  networking.nat = {
    enable = true;
    internalInterfaces = ["virbr0"];
  };

  systemd.network = {
    netdevs."virbr0".netdevConfig = {
      Kind = "bridge";
      Name = "virbr0";
    };
    networks."virbr0" = {
      matchConfig.Name = "virbr0";
      networkConfig.DHCPServer = true;
      addresses = [
        {
          addressConfig.Address = "192.168.100.1/24";
        }
      ];
    };
    # Connect VM tun/tap device to the bridge
    networks."11-netvm" = {
      matchConfig.Name = "vm-*";
      networkConfig.Bridge = "virbr0";
    };
  };
}
