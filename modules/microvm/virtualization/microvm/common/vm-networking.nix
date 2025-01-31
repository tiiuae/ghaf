# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  vmName,
  isGateway ? false,
  ...
}:
let
  interfaceName = "ethint0";
  inherit (config.ghaf.networking) hosts;
  netVmAddress = hosts."net-vm".ipv4;
  isIdsvmEnabled = config.ghaf.virtualization.microvm.idsvm.enable;
  idsVmAddress = hosts."ids-vm".ipv4;
  gateway = if isIdsvmEnabled && (vmName != "ids-vm") then [ idsVmAddress ] else [ netVmAddress ];
in
{
  networking = {
    hostName = vmName;
    enableIPv6 = false;
    firewall.allowedTCPPorts = [ 22 ];
    firewall.allowedUDPPorts = [ 67 ];
    useNetworkd = true;
    nat = {
      enable = true;
      internalInterfaces = [ interfaceName ];
    };
  };

  microvm.interfaces = [
    {
      type = "tap";
      # The interface names must have maximum length of 15 characters
      id = "tap-${vmName}";
      inherit (hosts.${vmName}) mac;
    }
  ];

  systemd.network = {
    enable = true;
    # Set internal network's interface name
    links."10-${interfaceName}" = {
      matchConfig.PermanentMACAddress = hosts.${vmName}.mac;
      linkConfig.Name = interfaceName;
    };
    networks."10-${interfaceName}" = {
      matchConfig.MACAddress = hosts.${vmName}.mac;
      addresses = [ { Address = "${hosts.${vmName}.ipv4}/24"; } ];
      linkConfig.RequiredForOnline = "routable";
      linkConfig.ActivationPolicy = "always-up";
    } // lib.optionalAttrs (!isGateway) { inherit gateway; };
  };

  # systemd-resolved does not support local names resolution
  # without configuring a local domain. With the local domain,
  # one would need also to disable DNSSEC for the clients.
  # Disabling DNSSEC for other VM then NetVM is
  # completely safe since they use NetVM as DNS proxy.
  services.resolved.dnssec = "false";
}
