# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.ghaf.graphics;
in {
  imports = [
    ./weston.nix
    ./labwc.nix
    ./gnome.nix
  ];

  options.ghaf.graphics = {
    #Make it possible to define a headless configuration
    enable = lib.mkEnableOption "Enable graphics on the platform";

    displayManager = lib.mkOption {
      type = lib.types.enum ["weston" "gnome" "labwc"];
      default = "weston";
      description = ''
        The display manager/compositor that is to be used for the desktop.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    #Enable one of the required display managers to supports graphics stack
    ghaf.graphics.weston.enable = cfg.displayManager == "weston";
    ghaf.graphics.gnome.enable = cfg.displayManager == "gnome";
    ghaf.graphics.labwc.enable = cfg.displayManager == "labwc";

    fonts.packages = with pkgs; [
      fira
      fira-code
      hack-font
    ];
    # Install a modern terminal
    environment.systemPackages = [pkgs.kitty];
  };
}
