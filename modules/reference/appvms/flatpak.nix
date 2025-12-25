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
  # XDG item for URL
  xdgUrlFlatpakItem = pkgs.makeDesktopItem {
    name = "ghaf-url-xdg-flatpak";
    desktopName = "Ghaf URL Opener";
    exec = "${urlScript}/bin/xdgflatpakurl %u";
    mimeTypes = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    noDisplay = true;
  };
  urlScript = pkgs.writeShellApplication {
    name = "xdgflatpakurl";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      url="$1"

      if [[ -z "$url" ]]; then
        echo "xdgflatpakurl: No URL provided"
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

      start_flatpak_browser() {
        local browsers="com.google.Chrome org.chromium.Chromium org.mozilla.firefox com.brave.Browser com.opera.Opera"
        local browser=""

        for app in $browsers; do
            if ${lib.getExe pkgs.flatpak} info --system "$app" 1>/dev/null 2>&1; then
                browser="$app"
                break
            fi
        done
        if [[ -z "$browser" ]]; then
            return 1
        fi
        if [ "$browser" = "org.mozilla.firefox" ]; then
          options="--new-window"
        else
          options="--disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland"
        fi

        XDG_SESSION_TYPE="wayland" WAYLAND_DISPLAY="wayland-1" DISPLAY=":0" ${config.ghaf.givc.appPrefix}/run-waypipe \
              ${lib.getExe pkgs.flatpak} run "$browser" \
                "$options" "$url"
        return 0
      }

      # Attempt to open URL in an App Store browser
      if ! start_flatpak_browser; then

        echo "No supported App Store browser found, trying local browsers..."
        # Try to detect locally installed available browsers
        if search_bin google-chrome-stable; then
          echo "Google Chrome detected, opening URL locally."
          start_browser google-chrome-stable
        elif search_bin chromium; then
          echo "Chromium detected, opening URL locally."
          start_browser chromium
        else
          echo "No supported browser found on the system"
          # Assignment in order to avoid build warning
          if ${lib.getExe pkgs.yad} --title="No App Store Browser Found" \
              --image=dialog-warning \
              --width=500 \
              --text="<b>No browser installed through App Store was found in this VM.</b>\n\nFor optimal security and functionality, please install a browser:\n  • Firefox\n  • Chrome\n  • Brave\n  • Chromium\n\nInstall from the App Store and try again.\n\n<i>Alternatively, continue with the standard browser (may malfunction).</i>" \
              --button="Exit:0" \
              --button="Continue:1" \
              --button-layout=spread \
              --center;
          then # user chose to exit
            exit 1
          else # user chose to continue
            ${config.ghaf.givc.appPrefix}/xdg-open-ghaf url "$url"
          fi
        fi
      fi

    '';
  };
  # XDG item for slack://
  xdgSlackFlatpakItem = pkgs.makeDesktopItem {
    name = "ghaf-slack-xdg-flatpak";
    desktopName = "Ghaf Slack Opener";
    exec = "${slackScript}/bin/xdgflatpakslack %u";
    mimeTypes = [
      "x-scheme-handler/slack"
    ];
    noDisplay = true;
  };
  slackScript = pkgs.writeShellApplication {
    name = "xdgflatpakslack";
    text = ''
      url="$*"
      [[ -z "$url" ]] && { echo "xdgflatpakslack: No URL provided" >&2; exit 1; }

      app="com.slack.Slack"

      ${lib.getExe pkgs.flatpak} info --system "$app" &>/dev/null || {
        echo "xdgflatpakslack: Slack not installed" >&2
        exit 1
      }

      exec ${lib.getExe pkgs.flatpak} run "$app" "$url"    '';
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
        description = "App Store to install Flatpak applications";
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

        environment.systemPackages = [
          xdgUrlFlatpakItem
          xdgSlackFlatpakItem
        ];

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

        xdg = {
          portal = {
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
          mime = {
            enable = true;
            defaultApplications = {
              "text/html" = lib.mkForce "ghaf-url-xdg-flatpak.desktop";
              "x-scheme-handler/http" = lib.mkForce "ghaf-url-xdg-flatpak.desktop";
              "x-scheme-handler/https" = lib.mkForce "ghaf-url-xdg-flatpak.desktop";
              "x-scheme-handler/slack" = lib.mkForce "ghaf-slack-xdg-flatpak.desktop";
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
