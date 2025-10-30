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
  #TODO; make sure that the lib is exported correctly and remove this cross file import
  inherit (import ../../lib/launcher.nix { inherit pkgs lib; }) rmDesktopEntries;
in
{
  options.ghaf.development.debug.tools.gui = {
    enable = lib.mkEnableOption "Enable GUI Debugging Tools";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux")
        (rmDesktopEntries [
          pkgs.intel-gpu-tools
          pkgs.vulkan-tools
          pkgs.glmark2
          pkgs.clinfo
          #pkgs.nvtopPackages.full
        ]);
  };
}
