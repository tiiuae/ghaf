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
  inherit (config.ghaf.services.audio) pulseaudioTcpControlPort;
in
{
  options.ghaf.reference.desktop.applications = {
    enable = lib.mkEnableOption "desktop applications";
  };
  config = lib.mkIf cfg.enable {
    ghaf.virtualization.microvm.guivm.applications =
      [
        {
          name = "Calculator";
          description = "Solve Math Problems";
          icon = "${pkgs.gnome-calculator}/share/icons/hicolor/scalable/apps/org.gnome.Calculator.svg";
          command = "${pkgs.gnome-calculator}/bin/gnome-calculator";
        }

        {
          name = "Sticky Notes";
          description = "Sticky Notes on your Desktop";
          icon = "${pkgs.sticky-notes}/share/icons/hicolor/scalable/apps/com.vixalien.sticky.svg";
          command = "${pkgs.sticky-notes}/bin/com.vixalien.sticky";
        }

        {
          name = "File Manager";
          description = "Organize & Manage Files";
          icon = "system-file-manager";
          command = "${pkgs.pcmanfm}/bin/pcmanfm";
        }

        {
          name = "Bluetooth Settings";
          description = "Manage Bluetooth Devices & Settings";
          icon = "bluetooth-48";
          command = "${pkgs.bt-launcher}/bin/bt-launcher";
        }

        {
          name = "Audio Control";
          description = "System Audio Control";
          icon = "preferences-sound";
          command = "${pkgs.ghaf-audio-control}/bin/GhafAudioControlStandalone --pulseaudio_server=audio-vm:${toString pulseaudioTcpControlPort} --indicator_icon_name=preferences-sound";
        }

        {
          name = "Falcon AI";
          description = "Your local large language model, developed by TII";
          icon = "${pkgs.ghaf-artwork}/icons/falcon-icon.svg";
          command = "${pkgs.alpaca}/bin/alpaca";
        }

        {
          name = "Control panel";
          description = "Control panel";
          icon = "utilities-tweak-tool";
          command = "${pkgs.ctrl-panel}/bin/ctrl-panel";
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
