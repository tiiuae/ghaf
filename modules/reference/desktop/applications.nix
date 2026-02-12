# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./applications.nix;

  options.ghaf.reference.desktop.applications = {
    enable = mkEnableOption "desktop applications";
  };
  config = mkIf cfg.enable {
    ghaf.hardware.definition.guivm.extraModules = [
      {
        # Default desktop files are always preferred
        environment.systemPackages = with pkgs; [
          gnome-calculator
          sticky-notes
        ];
      }
    ];
    ghaf.virtualization.microvm.guivm.applications = [
      {
        name = ".blueman-manager-wrapped";
        desktopName = "Bluetooth Settings";
        categories = [
          "System"
          "Settings"
        ];
        description = "Manage Bluetooth Devices & Settings";
        icon = "bluetooth-48";
        exec = "${pkgs.writeShellScriptBin "bluetooth-settings" ''
          DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock \
          PULSE_SERVER=audio-vm:${toString config.ghaf.services.audio.server.pulseaudioTcpControlPort} \
          ${pkgs.blueman}/bin/blueman-manager
        ''}/bin/bluetooth-settings";
      }

      {
        name = "ctrl-panel";
        desktopName = "Ghaf Control Panel";
        categories = [
          "System"
          "Settings"
        ];
        description = "Ghaf Control Panel";
        icon = "utilities-tweak-tool";
        exec = "${pkgs.ctrl-panel}/bin/ctrl-panel ${config.ghaf.givc.cliArgs}";
      }
    ]
    ++ lib.optionals config.ghaf.reference.services.alpaca-ollama [
      {
        name = "com.jeffser.Alpaca";
        desktopName = "Falcon AI";
        categories = [
          "Utility"
          "Development"
          "Chat"
        ];
        description = "Your local large language model, developed by TII";
        icon = "${pkgs.ghaf-artwork}/icons/falcon-icon.svg";
        exec = "${falcon-launcher}/bin/falcon-launcher";
      }
    ]
    ++ lib.optionals config.ghaf.reference.programs.windows-launcher.enable (
      let
        winConfig = config.ghaf.reference.programs.windows-launcher;
      in
      [
        {
          name = "Windows";
          desktopName = "Windows";
          description = "Virtualized Windows System";
          icon = "distributor-logo-windows";
          exec = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
        }
      ]
    );
  };
}
