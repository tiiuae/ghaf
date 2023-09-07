# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.development.debug.tools;
in
  with lib; {
    options.ghaf.development.debug.tools = {
      enable = mkEnableOption "Debug Tools";
    };

    config = mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        # For lspci:
        pciutils

        # For lsusb:
        usbutils

        # Useful in NetVM
        ethtool

        # Basic monitors
        htop
        iftop
        iotop

        traceroute
        dig
        evtest
      ];
    };
  }
