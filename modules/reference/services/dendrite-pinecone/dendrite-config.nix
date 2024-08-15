# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  config.ghaf.reference.services.dendrite-pinecone =
    let
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
            vmName = "net-vm";
            inherit (config.microvm.net-vm) macAddress;
            internalIP = 1;
          };
        in
        "${lib.head vmNetworking.networking.nat.internalInterfaces}";

      getElementVmEntry = builtins.filter (
        x: x.name == "element-vm"
      ) config.ghaf.networking.hosts.entries;
      serverIpAddr = lib.head (builtins.map (x: x.ip) getElementVmEntry);
    in
    {
      enable = lib.mkDefault false;
      inherit externalNic;
      inherit internalNic;
      inherit serverIpAddr;
    };
}
