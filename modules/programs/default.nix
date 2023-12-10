# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.programs;
in {
  # TODO
  # Define apps
  # Enable All Apps
  # Enable Select apps
  # Host only apps
  # Virtualized apps

  imports = [
    ./chromium.nix
    ./element-desktop.nix
    ./firefox.nix
    ./gala.nix
    ./terminal.nix
    ./zathura.nix
  ];

  options.ghaf.programs = {
    # Enable all apps for simplicity
    # However, apps can be enabled individually as needed
    enableAllApps = lib.mkEnableOption "Build all the demo applications";
  };

  config = lib.mkIf cfg.enableAllApps {
    ghaf.programs.chromium.enable = true;
    ghaf.programs.element-desktop.enable = true;
    ghaf.programs.firefox.enable = true;
    ghaf.programs.gala.enable = true;
    ghaf.programs.terminal.enable = true;
    ghaf.programs.zathura.enable = true;
  };
}
