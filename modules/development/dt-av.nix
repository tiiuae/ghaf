# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.debug.tools.av;
  inherit (lib) rmDesktopEntries;
in
{
  _file = ./dt-av.nix;

  options.ghaf.development.debug.tools.av.enable = lib.mkEnableOption "Camera Debugging Tools";

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux")
        (rmDesktopEntries [
          pkgs.v4l-utils
          pkgs.ffmpeg
        ]);
  };
}
