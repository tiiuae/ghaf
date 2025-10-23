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
    vtpm = {
      enable = true;
      runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
      basePort = 9170;
    };
    applications = [
      {
        name = "App Store";
        description = "Appstore to install Flatpak applications";
        packages = [
          pkgs.cosmic-store
        ];

        icon = "rocs";
        command = "cosmic-store";
      }
    ];
    extraModules = [
      {
        services.flatpak.enable = true;
        security.rtkit.enable = true;
        services.packagekit.enable = true;

        security.polkit = {
          enable = true;
          debug = true;
          extraConfig = ''
              polkit.addRule(function(action, subject) {
                if (action.id.startsWith("org.freedesktop.Flatpak.") &&
                    subject.user == "${config.ghaf.users.appUser.name}") {
                      return polkit.Result.YES;
                }
            });
          '';
        };

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
          description = "Add Flathub system-wide Flatpak repository";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
          };
          path = [ pkgs.flatpak ];
          script = ''
            flatpak --system remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            flatpak update --appstream --system
          '';
        };
      }
    ];
  };
}
