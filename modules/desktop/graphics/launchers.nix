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
    launcherVmIcons = mkOption {
      description = "Badge color and icon name per app VM, keyed by VM name without the -vm suffix.";
      internal = true;
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            color = mkOption {
              description = "Fill color of the generated badge, used only when icon is null.";
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            icon = mkOption {
              description = "Icon name for the badge, looked up in the icon themes available on the system.";
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
          };
        }
      );
      default = { };
    };
  };
}
