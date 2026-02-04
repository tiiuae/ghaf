# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  _file = ./default.nix;

  imports = [
    ./server.nix
    ./client.nix
  ];

  options.ghaf.services.audio = {
    enable = lib.mkEnableOption "Enable Ghaf audio services";
    role = lib.mkOption {
      type = lib.types.enum [
        "server"
        "client"
      ];
      default = "client";
      description = ''
        The role of this VM in the Ghaf audio topology.
        - "server" controls audio hardware and runs the main audio server
        - "client" connects to the audio server to play/record (and optionally control) audio
      '';
    };
  };
}
