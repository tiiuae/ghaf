# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib) optionalAttrs hasAttrByPath;
  isHost = hasAttrByPath [
    "hardware"
    "devices"
  ] config.ghaf;
in
{
  config.ghaf.reference.services.dendrite-pinecone = optionalAttrs isHost {
    enable = lib.mkDefault false;
    externalNic = (lib.head config.ghaf.hardware.definition.network.pciDevices).name;
    internalNic = "ethint0";
    serverIpAddr = config.ghaf.networking.hosts."comms-vm".ipv4;
  };
}
