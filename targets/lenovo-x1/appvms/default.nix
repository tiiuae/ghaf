# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  ...
}: let
  chromium = import ./chromium.nix {inherit pkgs;};
  gala = import ./gala.nix {inherit pkgs;};
  zathura = import ./zathura.nix {inherit pkgs;};
  element = import ./element.nix {inherit pkgs;};
  includeAppflowy = pkgs.stdenv.isx86_64;
  appflowy =
    if includeAppflowy
    then import ./appflowy.nix {inherit pkgs config;}
    else {};
  appvms =
    [
      chromium
      gala
      zathura
      element
    ]
    ++ pkgs.lib.optional includeAppflowy appflowy;
in
  appvms
