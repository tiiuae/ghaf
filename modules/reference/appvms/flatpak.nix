# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flatpak App Store VM
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.flatpak;
  onLaptop = config.ghaf.profiles.laptop-x86.enable or false;
  onOrin = config.ghaf.profiles.orin.enable or false;
  mkAppVm =
    if onLaptop then config.ghaf.profiles.laptop-x86.mkAppVm else config.ghaf.profiles.orin.mkAppVm;

  needsNetwork = lib.any (remote: !lib.hasPrefix "file://" remote.url) cfg.remotes;

  # Unresolved, for whoever builds installing from a local medium on top of
  # `remotes`: GIVC runs app-VM commands as appUser, so `flatpak install
  # --system` goes through the polkit rule below rather than running as root;
  # and whether installing a newer single-file .flatpak over an installed ref
  # upgrades it or errors is untested, which decides whether an offline medium
  # should carry an ostree repo or plain bundles.

  runCosmicStore = pkgs.writeShellApplication {
    name = "run-cosmic-store";
    text = ''
      # PATH override is needed for apps to launch from app store directly
      # TODO: Investigate
      export PATH=/run/wrappers/bin:/run/current-system/sw/bin
      # Quite verbose by default, so we set the logging to error
      RUST_LOG=error ${pkgs.cosmic-store}/bin/cosmic-store
    '';
  };

  flatpakManager = pkgs.writeShellApplication {
    name = "flatpak-manager";
    runtimeInputs = [ pkgs.flatpak ];
    text = ''
      action="$1"
      app="''${2#http://}"

      if [[ -z "$action" ]] || [[ -z "$app" ]]; then
        echo "Usage: flatpak-manager <run|uninstall|kill> <app-id>"
        exit 1
      fi

      case "$action" in
        run)
          # Ensure session D-Bus is available so apps can detect the SNI tray
          # watcher (org.kde.StatusNotifierWatcher) and show tray-related settings.
          # GIVC services run without a user session environment, so we derive
          # the bus address from XDG_RUNTIME_DIR or fall back to UID 1000.
          _uid=$(id -u)
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/''${_uid}/bus"
          export XDG_RUNTIME_DIR="/run/user/''${_uid}"
          FLATPAK_APPS="/var/lib/flatpak/exports/share/applications"
          desktop_file=$(find "$FLATPAK_APPS" -name "$app.desktop" 2>/dev/null | head -n 1)

          if [[ -z "$desktop_file" ]]; then
            echo "No .desktop file found for $app"
            echo "Will attempt to run the app optimistically with the app ID as command"
            exec_cmd="flatpak run $app"
          else
            exec_cmd=$(grep -E '^Exec=' "$desktop_file" | head -n 1 | cut -d'=' -f2-)
          fi

          if [[ -z "$exec_cmd" ]]; then
            echo "No Exec line found in $desktop_file"
            echo "Will attempt to run the app optimistically with the app ID as command"
            exec_cmd="flatpak run $app"
          fi

          # Strip .desktop field codes
          filtered_args=()
          first=true
          for token in $exec_cmd; do
            if [[ "$first" == true ]]; then
              filtered_args+=("$token")
              first=false
            elif [[ "$token" != %* ]]; then
              filtered_args+=("$token")
            fi
          done

          echo "Running: ''${filtered_args[*]}"
          exec env "''${filtered_args[@]}"
          ;;

        uninstall)
          echo "Uninstall for $app requested"
          echo "Killing any possible running instances of $app"
          flatpak kill "$app" || true
          echo "Uninstalling $app"
          flatpak uninstall --system --noninteractive --force-remove --delete-data "$app"
          echo "Uninstall complete"
          ;;

        kill)
          echo "Force quitting $app..."
          flatpak kill "$app"
          ;;

        *)
          echo "Unknown action: $action"
          echo "Valid actions: run, uninstall, kill"
          exit 1
          ;;
      esac
    '';
  };

  installFlatpakShare = pkgs.writeShellApplication {
    name = "install-flatpak-share";
    text = ''
          UNSAFE_SHARE_DIR="/home/${config.ghaf.users.appUser.name}/Unsafe share/.flatpak-share"
          DESKTOP_DIR="$UNSAFE_SHARE_DIR/share/applications"
          EXPORTS_DIR="/var/lib/flatpak/exports/share"

          [[ ! -d "$EXPORTS_DIR" ]] && exit 0

          rm -rf "$UNSAFE_SHARE_DIR"
          mkdir -p "$UNSAFE_SHARE_DIR"

          # Copy flatpak export shares to the Unsafe share
          cp -rL "$EXPORTS_DIR" "$UNSAFE_SHARE_DIR" \
            && echo "Copied flatpak 'exports/share' to $UNSAFE_SHARE_DIR" \
            || echo "Failed to copy flatpak desktop entries to $UNSAFE_SHARE_DIR"

          add_desktop_actions() {
            # Action display names
            declare -A ACTION_NAMES=(
              [uninstall]="Uninstall"
              [force-quit]="Force Quit"
            )
            desktop="$1"
            app_id="$2"
            shift 2
            actions=("$@")

            actions_value=$(printf '%s;' "''${actions[@]}")

            if grep -q '^Actions=' "$desktop"; then
              sed -i "s|^Actions=.*|Actions=$actions_value|" "$desktop"
            else
              sed -i "/^\[Desktop Entry\]/a Actions=$actions_value" "$desktop"
            fi

            for action in "''${actions[@]}"; do
              local name="''${ACTION_NAMES[$action]:-$action}"
              cat >> "$desktop" << EOF

      [Desktop Action $action]
      Name=$name
      Exec=ghaf-open flatpak-$action -- http://$app_id
      EOF
            done
          }

          # Fix desktop entry Exec fields to run from gui-vm
          if [[ -d "$DESKTOP_DIR" ]]; then
            for desktop in "$DESKTOP_DIR"/*.desktop; do
              # Skip if no .desktop files exist
              [[ -e "$desktop" ]] || continue

              # Extract the base name (APP-ID) without .desktop
              app_id="$(basename "$desktop" .desktop)"

              # Validate app_id to prevent path traversal or injection
              if [[ ! "$app_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                echo "Skipping suspicious desktop file: $desktop"
                rm -f "$desktop"
                continue
              fi

              # Fixup Exec, remove TryExec and Path, strip existing action sections
              sed -i \
                "s|^Exec=.*|Exec=ghaf-open flatpak-run -- http://$app_id|; \
                s|^TryExec=.*||; \
                s|^Path=.*||; \
                /^\[Desktop Action/,/^\[/{/^Exec=/d}" "$desktop"

              # Add VM labels while preserving localizations
              sed -i "s|^Name\(.*\)=\(.*\)|Name\1=[flatpak] \2|" "$desktop"

              add_desktop_actions "$desktop" "$app_id" "uninstall" "force-quit"
            done
            echo "Updated Exec lines in .desktop files under $DESKTOP_DIR"
          else
            echo "No desktop files found in $DESKTOP_DIR"
          fi
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
        "${config.ghaf.givc.appPrefix}/$1" --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland "$url"
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
          options=(--new-window)
        else
          options=(--disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland)
        fi

        ${lib.getExe pkgs.flatpak} run "$browser" "''${options[@]}" "$url"
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
              --buttons-layout=spread \
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
in
{
  _file = ./flatpak.nix;

  options.ghaf.reference.appvms.flatpak = {
    enable = lib.mkEnableOption "Flatpak App Store VM";

    remotes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name the remote is registered under.";
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = "Repository location, either a URL or a `file://` path.";
            };
            gpgVerify = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether to verify signatures from this remote. A local ostree
                repository assembled offline is usually unsigned.
              '';
            };
          };
        }
      );
      default = [
        {
          name = "flathub";
          url = "https://flathub.org/repo/flathub.flatpakrepo";
        }
      ];
      example = lib.literalExpression ''
        [
          {
            name = "local";
            url = "file:///mnt/ssd/repo";
            gpgVerify = false;
          }
        ]
      '';
      description = ''
        Flatpak remotes to register in the VM. An empty list registers none and
        generates no unit at all, for a device whose applications arrive by
        other means.
      '';
    };

    store.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to offer the App Store application. A device that must not have
        arbitrary software installed on it has no use for the entry.
      '';
    };
  };

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && (onLaptop || onOrin)) {
    # DRY: Only enable and evaluatedConfig at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.flatpak = {
      enable = lib.mkDefault true;

      evaluatedConfig = mkAppVm {
        name = "flatpak";
        mem = 6144;
        vcpu = 4;
        bootPriority = "low";
        borderColor = "#FFA500";
        ghafAudio.enable = lib.mkDefault true;
        vtpm.enable = lib.mkDefault true;
        permitStartApplication = lib.mkDefault true;
        applications =
          let
            flatpakManagerApp = action: {
              name =
                {
                  "run" = "flatpak-run";
                  "uninstall" = "flatpak-uninstall";
                  "kill" = "flatpak-force-quit";
                }
                .${action};
              desktopName = "${action} Flatpak App";
              description = "${action} a Flatpak application by its app ID";
              exec = "flatpak-manager ${action}";
              packages = [
                pkgs.flatpak
                flatpakManager
              ];
              givcArgs = [ "url" ];
              noDisplay = true;
            };
          in
          lib.optional cfg.store.enable {
            name = "com.system76.CosmicStore";
            desktopName = "App Store";
            categories = [
              "System"
              "PackageManager"
            ];
            description = "App Store to install Flatpak applications";
            packages = [ runCosmicStore ];
            icon = "rocs";
            exec = "run-cosmic-store";
          }
          ++ map flatpakManagerApp [
            "run"
            "uninstall"
            "kill"
          ];
        extraModules = [
          {
            ghaf.givc.sni.enable = true;
            services = {
              flatpak.enable = lib.mkDefault true;
              packagekit.enable = lib.mkDefault true;
            };
            security = {
              rtkit.enable = lib.mkForce true;
              polkit = {
                enable = lib.mkDefault true;
                extraConfig = ''
                    polkit.addRule(function(action, subject) {
                      if (action.id.startsWith("org.freedesktop.Flatpak.") &&
                          subject.user == "${config.ghaf.users.appUser.name}") {
                            return polkit.Result.YES;
                      }
                  });
                '';
              };
            };
            ghaf = {
              xdgitems.enable = lib.mkDefault true;

              theming.cosmic.enable = lib.mkDefault true;

              users.appUser.extraGroups = [
                "flatpak"
              ];

              # For persistant storage
              storagevm = {
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
            };

            environment.systemPackages = [
              xdgUrlFlatpakItem
            ];

            xdg = {
              portal = {
                xdgOpenUsePortal = true;
                enable = lib.mkDefault true;
                extraPortals = [
                  pkgs.xdg-desktop-portal-gtk
                ];
                config.common.default = [
                  "gtk"
                ];
              };
              mime = {
                enable = lib.mkDefault true;
                defaultApplications = {
                  "text/html" = lib.mkForce "ghaf-url-xdg-flatpak.desktop";
                  "x-scheme-handler/http" = lib.mkForce "ghaf-url-xdg-flatpak.desktop";
                  "x-scheme-handler/https" = lib.mkForce "ghaf-url-xdg-flatpak.desktop";
                };
              };
            };

            programs.dconf.enable = lib.mkDefault true;

            systemd = {
              services = {
                flatpak-repo = lib.mkIf (cfg.remotes != [ ]) {
                  description = "Add system-wide Flatpak repositories";
                  wantedBy = [ "multi-user.target" ];
                  # Only wait for the network if a remote actually needs it,
                  # otherwise an offline device blocks on a target that is
                  # never reached.
                  after = lib.optional needsNetwork "network-online.target";
                  requires = lib.optional needsNetwork "network-online.target";
                  serviceConfig = {
                    Type = "oneshot";
                    Restart = "on-failure";
                    RestartSec = "2s";
                  };
                  path = [ pkgs.flatpak ];
                  script = ''
                    ${lib.concatMapStringsSep "\n" (
                      remote:
                      "flatpak remote-add --if-not-exists ${
                        lib.optionalString (!remote.gpgVerify) "--no-gpg-verify "
                      }${remote.name} ${remote.url}"
                    ) cfg.remotes}
                    flatpak update --appstream --noninteractive
                  '';
                };
                flatpak-share-installer = {
                  description = "Flatpak Share Installer";
                  serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${lib.getExe installFlatpakShare}";
                    User = "${config.ghaf.users.appUser.name}";
                  };
                };
              };

              paths.flatpak-apps-listener = {
                description = "Flatpak Apps Listener";
                wantedBy = [ "multi-user.target" ];
                # Trigger once at boot
                wants = [ "flatpak-share-installer.service" ];
                # And then watch for changes
                pathConfig = {
                  PathChanged = "/var/lib/flatpak/exports/share/applications";
                  Unit = "flatpak-share-installer.service";
                };
              };
            };
          }
        ];
      };
    };
  };
}
