# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) optionalAttrs hasAttrByPath;
  inherit (config.ghaf.networking) hosts;
  isHost = hasAttrByPath [
    "hardware"
    "devices"
  ] config.ghaf;
in
{
  _file = ./chromecast-config.nix;

  config.ghaf.reference.services.chromecast = optionalAttrs isHost {
    enable = lib.mkDefault false;
    # externalNic is deliberately not set. It used to be
    #   (lib.head config.ghaf.hardware.definition.network.pciDevices).name
    # which enumerates PCI-passthrough NICs and so always yielded the Wi-Fi
    # card; a wired uplink arrives via vhotplug at runtime and is not in that
    # list at all, so the value was simply wrong on any wired device. The
    # interface is now resolved at runtime by ghaf-uplink-resolver. Set
    # externalNic explicitly only to pin a specific rig.
    internalNic = hosts.${config.networking.hostName}.interfaceName;
  };
}
