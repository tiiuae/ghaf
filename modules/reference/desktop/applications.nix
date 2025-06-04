# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.desktop.applications;
  inherit (lib) mkIf mkEnableOption;
  falcon-launcher = pkgs.falcon-launcher.override {
    inherit (pkgs) ghaf-artwork;
  };
in
{
  options.ghaf.reference.desktop.applications = {
    enable = mkEnableOption "desktop applications";
  };
  config = mkIf cfg.enable {
    ghaf.virtualization.microvm.guivm.applications =
      [
        {
          name = "Calculator";
          description = "Solve Math Problems";
          icon = "${pkgs.gnome-calculator}/share/icons/hicolor/scalable/apps/org.gnome.Calculator.svg";
          command = "${pkgs.gnome-calculator}/bin/gnome-calculator";
        }

        {
          name = "Bluetooth Settings";
          description = "Manage Bluetooth Devices & Settings";
          icon = "bluetooth-48";
          command = "${pkgs.bt-launcher}/bin/bt-launcher";
        }

        {
          name = "Ghaf Control Panel";
          description = "Ghaf Control Panel";
          icon = "utilities-tweak-tool";
          command = "${pkgs.ctrl-panel}/bin/ctrl-panel ${config.ghaf.givc.cliArgs}";
        }

        # com.vixalien.sticky segfaults in COSMIC DE
        {
          name = "Sticky Notes";
          description = "Sticky Notes on your Desktop";
          icon = "${pkgs.sticky-notes}/share/icons/hicolor/scalable/apps/com.vixalien.sticky.svg";
          command = "${pkgs.sticky-notes}/bin/com.vixalien.sticky";
        }
      ]
      ++ lib.optionals (config.ghaf.profiles.graphics.compositor != "cosmic") [
        {
          name = "File Manager";
          description = "Organize & Manage Files";
          icon = "system-file-manager";
          command = "${pkgs.pcmanfm}/bin/pcmanfm";
        }
      ]
      ++ lib.optionals config.ghaf.reference.services.alpaca-ollama [
        {
          name = "Falcon AI";
          description = "Your local large language model, developed by TII";
          icon = "${pkgs.ghaf-artwork}/icons/falcon-icon.svg";
          command = "${pkgs.falcon-launcher}/bin/falcon-launcher";
        }
      ]
      ++ lib.optionals config.ghaf.reference.programs.windows-launcher.enable (
        let
          winConfig = config.ghaf.reference.programs.windows-launcher;
        in
        [
          {
            name = "Windows";
            description = "Virtualized Windows System";
            icon = "distributor-logo-windows";
            command = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
          }
        ]
      );
  };
}
