# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.host-hardening;
  has_host = builtins.hasAttr "host" config.ghaf;
  has_secureBoot = builtins.hasAttr "secureboot" config.ghaf.host;
in
{
  _file = ./host-hardening.nix;

  options.ghaf.profiles.host-hardening = {
    enable = lib.mkEnableOption "Host hardening profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf =
      { }
      // lib.optionalAttrs (has_host && has_secureBoot) {
        host = {
          # Enable secure boot in the host configuration
          secureboot.enable = true;
        };
      };
  };
}
