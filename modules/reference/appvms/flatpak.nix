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
  urlScript = pkgs.writeShellApplication {
    name = "xdgflatpakurl";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      url="$1"

      if [[ -z "$url" ]]; then
        echo "No URL provided - xdg handlers"
        exit 1
      fi

      echo "XDG open url: $url"

      # Function to check if a binary exists in the givc app prefix
      search_bin() {
        [ -x "${config.ghaf.givc.appPrefix}/$1" ]
      }

      start_browser() {
        ${config.ghaf.givc.appPrefix}/run-waypipe "${config.ghaf.givc.appPrefix}/$1" \
          --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland "$url"
      }

      start_flakpak_browser() {
        local browsers="com.google.Chrome org.chromium.Chromium"
        local browser=""

        for app in $browsers; do
            if ${pkgs.flatpak}/bin/flatpak info --system "$app" 1>>/dev/null; then
                browser="$app"
                break
            fi
        done
        if [[ -z "$browser" ]]; then
            return 1
        fi

        ${config.ghaf.givc.appPrefix}/run-waypipe \
            ${pkgs.flatpak}/bin/flatpak run "$browser" \
                --disable-gpu \
                --enable-features=UseOzonePlatform \
                --ozone-platform=wayland \
                "$url"
        return 0
      }

      # Attempt to open URL in a Flatpak browser
      if ! start_flakpak_browser; then

        echo "No supported Flatpak browser found, trying local browsers..."
        # Try to detect locally installed available browsers
        if search_bin google-chrome-stable; then
          echo "Google Chrome detected, opening URL locally."
          start_browser google-chrome-stable
        elif search_bin chromium; then
          echo "Chromium detected, opening URL locally."
          start_browser chromium
        else
          echo "No supported browser found on the system"
          ${pkgs.zenity}/bin/zenity --error --text="No compatible browser found.\n\nPlease install:\n- Chrome\n- Chromium" --title="Browser Error"
          return 1
        fi
      fi

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
        ghaf.xdgitems.enable = true;
        ghaf.xdghandlers.url = true;
        ghaf.xdghandlers.urlScript = "${urlScript}/bin/xdgflatpakurl";

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
          xdgOpenUsePortal = true;
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
