# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
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
            inherit config lib pkgs;
            vmName = "net-vm";
          };
        in
        "${lib.head vmNetworking.networking.nat.internalInterfaces}";

      serverIpAddr = config.ghaf.networking.hosts."comms-vm".ipv4;
    in
    {
      enable = lib.mkDefault false;
      inherit externalNic;
      inherit internalNic;
      inherit serverIpAddr;
    };
}
