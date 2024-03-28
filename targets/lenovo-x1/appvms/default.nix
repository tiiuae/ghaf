# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: let
  chromium = import ./chromium.nix {inherit pkgs;};
  gala = import ./gala.nix {inherit pkgs;};
  zathura = import ./zathura.nix {inherit pkgs;};
  element = import ./element.nix {inherit pkgs;};
in [
  chromium
  gala
  zathura
  element
]
