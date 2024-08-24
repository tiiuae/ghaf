# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  vmName,
  macAddress,
  internalIP,
  isGateway ? false,
  ...
}:
let
  networkName = "ethint0";
  netVmEntry = builtins.filter (x: x.name == "net-vm") config.ghaf.networking.hosts.entries;
  netVmAddress = builtins.map (x: x.ip) netVmEntry;
  isIdsvmEnabled = config.ghaf.virtualization.microvm.idsvm.enable;
  idsVmEntry = builtins.filter (x: x.name == "ids-vm") config.ghaf.networking.hosts.entries;
  idsVmAddress = lib.optionals isIdsvmEnabled (builtins.map (x: x.ip) idsVmEntry);
  gateway = if isIdsvmEnabled && (vmName != "ids-vm") then idsVmAddress else netVmAddress;
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
      internalInterfaces = [ networkName ];
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
      addresses =
        [ { Address = "192.168.100.${toString internalIP}/24"; } ]
        ++ lib.optionals config.ghaf.profiles.debug.enable [
          {
            # IP-address for debugging subnet
            Address = "192.168.101.${toString internalIP}/24";
          }
        ];
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
