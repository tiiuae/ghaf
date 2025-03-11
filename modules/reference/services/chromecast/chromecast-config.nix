# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  config.ghaf.reference.services.chromecast =
    let
      externalNic =
        let
          firstPciWifiDevice = lib.head config.ghaf.hardware.definition.network.pciDevices;
        in
        "${firstPciWifiDevice.name}";
      internalNic = "ethint0";
    in
    {
      enable = lib.mkDefault false;
      inherit externalNic;
      inherit internalNic;
    };
}
