# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  ...
}:
{
  flatpak = {
    ramMb = 6144;
    cores = 4;
    bootPriority = "low";
    borderColor = "#027d7b";
    applications = [
      {
        name = "APPStore";
        description = "Appstore to install Flatpak applications";
        packages = [
          pkgs.gnome-software
          pkgs.flatpak
        ];

        icon = "${pkgs.papirus-icon-theme}/share/icons/Papirus/64x64/apps/rocs.svg";
        command = "gnome-software";
      }
    ];
    extraModules = [
      {
        services.flatpak.enable = true;
        security.rtkit.enable = true;
        xdg.portal = {
          enable = true;
          extraPortals = [
            pkgs.xdg-desktop-portal-gtk
          ];
          config = {
            common = {
              default = [
                "gtk"
              ];
            };
          };
        };
        systemd.services.flatpak-repo = {
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.flatpak ];
          script = ''
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
          '';
        };

        imports = [
          ../services/wireguard-gui/wireguard-gui.nix
        ];
        # Enable WireGuard GUI
        ghaf.reference.services.wireguard-gui.enable = config.ghaf.reference.services.wireguard-gui;
      }
    ];
  };
}
