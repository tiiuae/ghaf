# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.debug.tools.net;
  inherit (lib) rmDesktopEntries;
in
{
  _file = ./dt-net.nix;

  options.ghaf.development.debug.tools.net = {
    enable = lib.mkEnableOption "Network Debugging Tools";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux")
        (rmDesktopEntries [
          # Useful in NetVM
          pkgs.ethtool
          pkgs.ookla-speedtest
          pkgs.iperf
          pkgs.dig
          pkgs.iftop
        ]);
  };
}
