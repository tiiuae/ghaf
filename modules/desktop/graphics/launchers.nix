# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  _file = ./launchers.nix;

  options.ghaf.graphics = {
    launchers = mkOption {
      description = "Application launchers to show in the system drawer or launcher.";
      default = [ ];
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              description = "Name of the application";
              type = types.str;
            };
            description = mkOption {
              description = "Description of the application";
              type = types.str;
              default = "Secured Ghaf Application";
            };
            vm = mkOption {
              description = "VM name in case this launches an isolated application.";
              type = types.nullOr types.str;
              default = null;
            };
            execPath = mkOption {
              description = "Path to the executable to be launched";
              type = types.path;
            };
            icon = mkOption {
              description = ''
                Optional icon for the launcher. If unspecified, active icon theme will
                be searched to find an icon matching the launcher name. Can be set to an
                icon name from the current theme (Papirus) or a full path to an icon file.
              '';
              type = types.nullOr (types.path // types.str);
              default = null;
            };
          };
        }
      );
    };
  };
}
