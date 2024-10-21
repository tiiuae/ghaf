# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  drawerCSS = pkgs.callPackage ./styles/launcher-style.nix { };
in
pkgs.writeShellApplication {
  name = "ghaf-launcher";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.nwg-drawer
    pkgs.util-linux
  ];
  bashOptions = [ ];
  text = ''
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"

    # Temporary workaround
    mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
    rm -rf "$HOME/.config/nwg-drawer"
    #ln -s "${drawerCSS}/nwg-drawer" "$HOME/.config/"

    nwg-drawer -r -nofs -nocats -s ${drawerCSS}
  '';
}
