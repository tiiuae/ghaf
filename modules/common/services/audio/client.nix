# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkEnableOption
    mkIf
    ;
  host = "gui-vm";
  address = "tcp:${host}:${toString 4715}";

in
{
  options.ghaf.services.audio = {
    client = mkEnableOption "";
  };

  config = mkIf cfg.client {
    environment = {
      systemPackages = [ pkgs.pulseaudio ];
      sessionVariables = {
        PULSE_SERVER = "${address}";
      };
      variables = {
        PULSE_SERVER = "${address}";
      };
    };
  };
}
