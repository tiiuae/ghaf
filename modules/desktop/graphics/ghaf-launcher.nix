# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellScriptBin,
  writeTextDir,
  coreutils,
  nwg-drawer,
  ...
}: let
  drawerCSS = writeTextDir "nwg-drawer/drawer.css" ''
    /* Example configuration from: https://github.com/nwg-piotr/nwg-drawer/blob/main/drawer.css */
    window {
        background-color: rgba (43, 48, 59, 0.95);
        color: #eeeeee
    }

    /* search entry */
    entry {
        background-color: rgba (0, 0, 0, 0.2)
    }

    button, image {
        background: none;
        border: none
    }

    button:hover {
        background-color: rgba (255, 255, 255, 0.1)
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
  writeShellScriptBin
  "ghaf-launcher"
  ''
    export XDG_CONFIG_HOME=${drawerCSS}
    export XDG_CACHE_HOME=$HOME/.cache
    ${coreutils}/bin/mkdir -p $XDG_CACHE_HOME
    ${nwg-drawer}/bin/nwg-drawer
  ''
