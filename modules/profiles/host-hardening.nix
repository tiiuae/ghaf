# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.host-hardening;
in
{
  _file = ./host-hardening.nix;

  options.ghaf.profiles.host-hardening = {
    enable = lib.mkEnableOption "Host hardening profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf.host = {
      # Enable secure boot in the host configuration
      secureboot.enable = true;
    };
  };
}
