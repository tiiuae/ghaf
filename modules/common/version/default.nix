# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generates an executable called ghaf-version which will print version
# information to stdout
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ghafVersion = pkgs.writeShellScriptBin "ghaf-version" ''
    echo "${config.ghaf.version}"
  '';
in
{
  _file = ./default.nix;

  options = {
    ghaf.version = lib.mkOption {
      type = lib.types.str;
      # TODO REPLACE ME with hash pointed to by /run/current-system in built image
      default = lib.strings.fileContents ../../../.version;
      readOnly = true;
      description = "The version of Ghaf";
    };
  };
  config = {
    environment.systemPackages = [ ghafVersion ];
  };
}
