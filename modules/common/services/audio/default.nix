# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  imports = [
    ./anchor.nix
    ./client.nix
    ./hub.nix
  ];

  options.ghaf.services.audio = {
    enable = lib.mkEnableOption "Enable Ghaf audio services";
    role = lib.mkOption {
      type = lib.types.enum [
        "anchor"
        "hub"
        "client"
      ];
      default = "client";
      description = ''
        The role of this VM in the Ghaf audio topology.
        - "anchor" provides physical audio devices
        - "hub" mediates audio to clients
        - "client" consumes audio from the hub
      '';
    };
  };
}
