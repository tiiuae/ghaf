# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  runAppCenter = pkgs.writeShellApplication {
    name = "run-flatpak";
    runtimeInputs = [
      pkgs.systemd
      pkgs.cosmic-store
    ];
    text = ''
      export XDG_SESSION_TYPE="wayland"
      export DISPLAY=":0"
      export PATH=/run/wrappers/bin:/run/current-system/sw/bin

      systemctl --user start run-xwayland
      systemctl --user set-environment WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
      systemctl --user restart xdg-desktop-portal-gtk.service

      cosmic-store
    '';
  };
in
{
  flatpak = {
    ramMb = 6144;
    cores = 4;
    bootPriority = "low";
    borderColor = "#FFA500";
    ghafAudio.enable = true;
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
          runAppCenter
        ];
        icon = "rocs";
        command = "run-flatpak";
      }
    ];
    extraModules = [
      {
        services.flatpak.enable = true;
        security.rtkit.enable = lib.mkForce true;
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

        ghaf.users.appUser.extraGroups = [
          "flatpak"
        ];

        # For persistant storage
        ghaf.storagevm = {
          directories = [
            {
              directory = "/var/lib/flatpak";
              user = "root";
              group = "root";
              mode = "0755";
            }
          ];
          maximumSize = 200 * 1024; # 200 GB space allocated
          mountOptions = [
            "rw"
            "nodev"
            "nosuid"
            "exec" # For Bubblewrap sandbox to execute the file
          ];
          users.${config.ghaf.users.appUser.name}.directories = [
            ".var" # For app data
          ];
        };

        programs.dconf.enable = true;

        systemd.services.flatpak-repo = {
          description = "Add Flathub system-wide Flatpak repository";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            Restart = "on-failure";
            RestartSec = "2s";
          };
          path = [ pkgs.flatpak ];
          script = ''
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            flatpak update --appstream --noninteractive
          '';
        };

        systemd.user.services."run-xwayland" = {
          description = "Grants rootless Xwayland integration to any Wayland compositor";
          serviceConfig = {
            ExecStart = "${config.ghaf.givc.appPrefix}/run-waypipe  ${lib.getExe pkgs.xwayland-satellite}";
            Restart = "on-failure";
            RestartSec = "2s";
          };
        };
      }
    ];
  };
}
