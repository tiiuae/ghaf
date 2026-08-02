# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib) optionalAttrs hasAttrByPath;
  inherit (config.ghaf.networking) hosts;
  isHost = hasAttrByPath [
    "hardware"
    "devices"
  ] config.ghaf;
in
{
  _file = ./dendrite-config.nix;

  config.ghaf.reference.services.dendrite-pinecone = optionalAttrs isHost {
    enable = lib.mkDefault false;
    # Not set: see the note in chromecast-config.nix. The interface is resolved
    # at runtime; set this explicitly only to pin a specific rig.
    internalNic = hosts.${config.networking.hostName}.interfaceName;
    serverIpAddr = config.ghaf.networking.hosts."comms-vm".ipv4;
  };
}
