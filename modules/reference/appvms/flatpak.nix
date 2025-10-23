# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
        name = "App Store";
        description = "Appstore to install Flatpak applications";
        packages = [
          pkgs.cosmic-store
        ];

        icon = "${pkgs.papirus-icon-theme}/share/icons/Papirus/64x64/apps/rocs.svg";
        command = "cosmic-store";
      }
    ];
    extraModules = [
      {
        services.flatpak.enable = true;
        security.rtkit.enable = true;
        xdg.portal = {
          enable = true;
          extraPortals = [
            pkgs.xdg-desktop-portal-cosmic
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
          description = "Add Flathub remote for Flatpak";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
          };
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
