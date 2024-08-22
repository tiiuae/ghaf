# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  drawerCSS = pkgs.writeTextDir "nwg-drawer/drawer.css" ''
    /* Example configuration from: https://github.com/nwg-piotr/nwg-drawer/blob/main/drawer.css */
    window {
        background-color: rgba(32, 32, 32, 0.9);
        color: #eeeeee;
        border-radius: 7px;
        border: 1px solid rgba(21, 36, 24, 0.3);
        box-shadow: rgba(100, 100, 111, 0.2) 0px 7px 29px 0px;
    }

    /* search entry */
    entry {
        background-color: rgba (43, 43, 43, 1);
        border: 1px solid rgba(46, 46, 46, 1);
    }
    entry:focus {
        box-shadow: none;
        border: 1px solid rgba(223, 92, 55, 1);
    }

    button, image {
        background: none;
        border: none;
        box-shadow: none;
    }

    button:hover {
        background-color: rgba (255, 255, 255, 0.06)
    }

    /* in case you wanted to give category buttons a different look */
    #category-button {
        margin: 0 10px 0 10px
    }

    #pinned-box {
        padding-bottom: 5px;
        border-bottom: 1px dotted gray
    }

    #files-box {
        padding: 5px;
        border: 1px dotted gray;
        border-radius: 15px
    }
  '';
in
pkgs.writeShellApplication {
  name = "ghaf-launcher";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.nwg-drawer
  ];
  bashOptions = [ ];
  text = ''
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"

    # Temporary workaround
    mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
    rm -rf "$HOME/.config/nwg-drawer"
    ln -s "${drawerCSS}/nwg-drawer" "$HOME/.config/"

    nwg-drawer -r -c 5 -mb 60 -ml 440 -mr 440 -mt 420 -nofs -nocats -ovl
  '';
}
