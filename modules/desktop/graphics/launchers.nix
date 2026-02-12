# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ lib, ... }:
let
  inherit (lib)
    mkOption
    ;
in
{
  _file = ./launchers.nix;

  options.ghaf.graphics = {
    launchers = mkOption {
      description = "Application launchers to show in the system drawer or launcher.";
      type = lib.types.listOf lib.types.ghafApplication;
      default = [ ];
    };
  };
}
