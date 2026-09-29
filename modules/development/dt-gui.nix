# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.debug.tools.gui;
  inherit (lib) rmDesktopEntries;
in
{
  _file = ./dt-gui.nix;

  options.ghaf.development.debug.tools.gui.enable = lib.mkEnableOption "GUI Debugging Tools";

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      with pkgs;
      [ lswt ]
      ++ lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux") (rmDesktopEntries [
        intel-gpu-tools
        vulkan-tools
        glmark2
        clinfo
        ydotool
        evtest
        #nvtopPackages.full
      ]);
  };
}
