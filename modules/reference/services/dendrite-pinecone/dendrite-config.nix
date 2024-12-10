# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  config.ghaf.reference.services.dendrite-pinecone =
    let
      hostsEntries = import ../../../common/networking/hosts-entries.nix;
      vmname = "net-vm";
      externalNic =
        let
          firstPciWifiDevice = lib.head config.ghaf.hardware.definition.network.pciDevices;
        in
        "${firstPciWifiDevice.name}";

      internalNic =
        let
          vmNetworking = import ../../../microvm/virtualization/microvm/common/vm-networking.nix {
            inherit config;
            inherit lib;
            vmName = vmname;
            inherit (config.microvm.net-vm) macAddress;
            internalIP = hostsEntries.ipByName vmname;
          };
        in
        "${lib.head vmNetworking.networking.nat.internalInterfaces}";

      getCommsVmEntry = builtins.filter (x: x.name == "comms-vm") config.ghaf.networking.hosts.entries;
      serverIpAddr = lib.head (builtins.map (x: x.ip) getCommsVmEntry);
    in
    {
      enable = lib.mkDefault false;
      inherit externalNic;
      inherit internalNic;
      inherit serverIpAddr;
    };
}
