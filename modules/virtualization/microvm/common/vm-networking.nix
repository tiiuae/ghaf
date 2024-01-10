# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  vmName,
  macAddress,
  ...
}: let
  networkName = "ethint0";
in {
  networking = {
    hostName = vmName;
    enableIPv6 = false;
    firewall.allowedTCPPorts = [22];
    firewall.allowedUDPPorts = [67];
    useNetworkd = true;
    nat = {
      enable = true;
      internalInterfaces = [networkName];
    };
  };

  microvm.interfaces = [
    {
      type = "tap";
      # The interface names must have maximum length of 15 characters
      id = "tap-${vmName}";
      mac = macAddress;
    }
  ];

  systemd.network = {
    enable = true;
    # Set internal network's interface name to networkName
    links."10-${networkName}" = {
      matchConfig.PermanentMACAddress = macAddress;
      linkConfig.Name = networkName;
    };
    networks."10-${networkName}" = {
      matchConfig.MACAddress = macAddress;
      DHCP = "yes";
      dhcpV4Config.UseDomains = "yes";
      linkConfig.RequiredForOnline = "routable";
      linkConfig.ActivationPolicy = "always-up";
    };
  };

  services.resolved = {
    # systemd-resolved does not support local names resolution
    # without configuring a local domain. With the local domain,
    # one would need also to disable DNSSEC for the clients.
    # Disabling DNSSEC for other VM then NetVM is
    # completely safe since they use NetVM as DNS proxy.
    dnssec = "false";
    # Disable local DNS stub listener on 127.0.0.53
    extraConfig = ''
      DNSStubListener=no
    '';
  };
}
