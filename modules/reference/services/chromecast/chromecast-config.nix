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
    internalNic = hosts.${config.networking.hostName}.interfaceName;
  };
}
