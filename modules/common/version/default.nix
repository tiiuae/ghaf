# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generates an executable called ghaf-version which will print version
# information to stdout
{
  pkgs,
  lib,
  ...
}: let
  ghafVersion = pkgs.writeShellScriptBin "ghaf-version" ''
    echo "${lib.ghaf-version}"
  '';
in {
  environment.systemPackages = [
    ghafVersion
  ];
}
