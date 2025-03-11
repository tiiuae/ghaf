# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.vm-networking;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    hasAttr
    ;
  inherit (config.ghaf.networking) hosts;

  isIdsvmEnabled = hasAttr "ids-vm" hosts;
  netVmAddress = hosts."net-vm".ipv4;
  idsVmAddress = hosts."ids-vm".ipv4;
  gateway = if isIdsvmEnabled && (cfg.vmName != "ids-vm") then [ idsVmAddress ] else [ netVmAddress ];
in
{
  options.ghaf.virtualization.microvm.vm-networking = {
    enable = mkEnableOption "Enable vm networking configuration";
    isGateway = mkEnableOption "Enable gateway configuration";
    vmName = mkOption {
      description = "Name of the VM";
      type = types.nullOr types.str;
    };
    interfaceName = mkOption {
      description = "Name of the internal interface";
      type = types.str;
      default = "ethint0";
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.vmName != null;
        message = "Missing VM name, try setting the option";
      }
    ];

    networking = {
      hostName = cfg.vmName;
      enableIPv6 = false;
      firewall.allowedTCPPorts = [ 22 ];
      firewall.allowedUDPPorts = [ 67 ];
      useNetworkd = true;
      nat = {
        enable = true;
        internalInterfaces = [ cfg.interfaceName ];
      };
    };

    microvm.interfaces = [
      {
        type = "tap";
        # The interface names must have maximum length of 15 characters
        id = "tap-${cfg.vmName}";
        inherit (hosts.${cfg.vmName}) mac;
      }
    ];

    systemd.network = {
      enable = true;
      # Set internal network's interface name
      links."10-${cfg.interfaceName}" = {
        matchConfig.PermanentMACAddress = hosts.${cfg.vmName}.mac;
        linkConfig.Name = cfg.interfaceName;
      };
      networks."10-${cfg.interfaceName}" = {
        matchConfig.MACAddress = hosts.${cfg.vmName}.mac;
        addresses = [ { Address = "${hosts.${cfg.vmName}.ipv4}/24"; } ];
        linkConfig.RequiredForOnline = "routable";
        linkConfig.ActivationPolicy = "always-up";
      } // lib.optionalAttrs (!cfg.isGateway) { inherit gateway; };
    };

    # systemd-resolved does not support local names resolution
    # without configuring a local domain. With the local domain,
    # one would need also to disable DNSSEC for the clients.
    # Disabling DNSSEC for other VM then NetVM is
    # completely safe since they use NetVM as DNS proxy.
    services.resolved.dnssec = "false";
  };
}
