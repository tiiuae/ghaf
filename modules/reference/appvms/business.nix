# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (lib)
    optionals
    getExe
    mkIf
    ;
  enableOpenNormalExtension = true;
in
{
  business = {
    packages = optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
    ramMb = 6144;
    cores = 4;
    borderColor = "#218838";
    ghafAudio.enable = true;
    vtpm.enable = true;
    applications =
      let
        inherit (config.microvm.vms."business-vm".config.config.ghaf.reference.services.pac) proxyPacUrl;

        withDebug = config.ghaf.profiles.debug.enable;

        # Select the browser package based on main browser VM configuration
        chromePackage =
          if config.ghaf.virtualization.microvm.appvm.vms.chrome.enable then
            pkgs.google-chrome
          else if config.ghaf.virtualization.microvm.appvm.vms.chromium.enable then
            pkgs.chromium
          else
            null;

        trustedBrowserWrapper = pkgs.writeShellApplication {
          name = "trusted-browser-wrapper";
          runtimeInputs = [
            pkgs.jq
            chromePackage
          ];

          text = ''
            if ${lib.boolToString withDebug}; then
                debug() { echo "[DEBUG] $*"; }
            else
                debug() { :; }  # no-op
            fi

            # Determine which browser binary we are using
            CHROME_BIN="${getExe chromePackage}"
            CHROME_NAME=$(basename "$CHROME_BIN")
            debug "Chrome binary: $CHROME_BIN"
            debug "Chrome name: $CHROME_NAME"

            if [[ "$CHROME_NAME" == *"chrome"* ]]; then
              CONFIG_BASE="$HOME/.config/google-chrome"
            elif [[ "$CHROME_NAME" == *"chromium"* ]]; then
              CONFIG_BASE="$HOME/.config/chromium"
            else
              CONFIG_BASE="$HOME/.config/$CHROME_NAME"
            fi
            debug "Config base directory: $CONFIG_BASE"

            PROFILE_NAME="Default"

            # Look for --profile-directory= in args
            for arg in "$@"; do
              case "$arg" in
                --profile-directory=*)
                  PROFILE_NAME="''${arg#--profile-directory=}"
                  ;;
              esac
            done
            debug "Using profile name: $PROFILE_NAME"

            PREFS="$CONFIG_BASE/$PROFILE_NAME/Preferences"
            debug "Preferences file path: $PREFS"
            mkdir -p "$(dirname "$PREFS")"

            # Create a minimal Preferences file if it doesn't exist
            if [ ! -f "$PREFS" ]; then
              debug "Preferences file does not exist. Creating minimal Preferences file."
              echo '{}' > "$PREFS"
            fi

            BASE_FILTER='
              .browser |= . // {}
              | .browser.custom_chrome_frame = false
            '

            # Add profile name only if not "Default"
            if [ "$PROFILE_NAME" != "Default" ]; then
              JQ_FILTER="$BASE_FILTER
                | .profile |= . // {}
                | .profile.name = \"$PROFILE_NAME\""
            else
              JQ_FILTER="$BASE_FILTER"
            fi

            # TODO: Remove this block after October 2025
            # It's only needed to migrate users who installed the extension prior to v1.0.1
            if ${lib.boolToString enableOpenNormalExtension}; then
              EXTENSIONS_FILTER='
                | .extensions |= . // {}
                | .extensions.pinned_extensions |= (. + ["${pkgs.open-normal-extension.id}"] | unique)
                | .extensions.settings |= . // {}
                | .extensions.settings["${pkgs.open-normal-extension.id}"] |= . // {}
                | .extensions.settings["${pkgs.open-normal-extension.id}"].manifest |= . // {}
                | .extensions.settings["${pkgs.open-normal-extension.id}"].manifest.update_url |= . // "http://localhost:8080/update.xml"
              '
              JQ_FILTER="$JQ_FILTER $EXTENSIONS_FILTER"
            fi
            # TODO: Remove this block after October 2025


            debug "jq filter being applied:"
            debug "$JQ_FILTER"

            jq "$JQ_FILTER" "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"
            debug "Preferences updated successfully."

            # Launch the browser
            debug "Launching Chrome..."
            "$CHROME_BIN" --enable-features=UseOzonePlatform \
              --ozone-platform=wayland \
              --disable-gpu \
              ${config.ghaf.givc.idsExtraArgs} \
              --proxy-pac-url=${proxyPacUrl} "$@"
          '';
        };
      in
      [
        {
          name = "Trusted Browser";
          description = "Isolated Trusted Browsing";
          packages = [ trustedBrowserWrapper ];
          icon = "thorium-browser";
          command = "trusted-browser-wrapper --profile-directory=TrustedBrowserProfile";
          givcArgs = [
            "url"
          ];
          extraModules = [
            {
              assertions = [
                {
                  assertion = chromePackage != null;
                  message = "Neither google-chrome nor chromium VM is enabled, business-vm will not have a browser.";
                }
              ];

              imports = [
                ../programs/chromium.nix
                ../programs/google-chrome.nix
              ];

              ghaf = {
                reference = {
                  programs.google-chrome = {
                    enable = chromePackage == pkgs.google-chrome;
                    openInNormalExtension = enableOpenNormalExtension;
                  };
                  programs.chromium = {
                    enable = chromePackage == pkgs.chromium;
                    openInNormalExtension = enableOpenNormalExtension;
                  };
                };

                xdgitems.enable = true;
                security.apparmor.enable = true;
              };
            }
          ];
        }
        {
          name = "Microsoft Outlook";
          description = "Microsoft Email Client";
          icon = "ms-outlook";
          command = "trusted-browser-wrapper --app=https://outlook.office.com/mail/ --profile-directory=OutlookProfile";
        }
        {
          name = "Microsoft 365";
          description = "Microsoft 365 Software Suite";
          icon = "microsoft-365";
          command = "trusted-browser-wrapper --app=https://microsoft365.com --profile-directory=M365Profile";
        }
        {
          name = "Teams";
          description = "Microsoft Teams Collaboration Application";
          icon = "teams-for-linux";
          command = "trusted-browser-wrapper --app=https://teams.microsoft.com --profile-directory=TeamsProfile";
        }
        {
          name = "Gala";
          description = "Secure Android-in-the-Cloud";
          icon = "distributor-logo-android";
          command = "trusted-browser-wrapper --app=https://gala.atrc.azure-atrc.androidinthecloud.net/#/login --profile-directory=GalaProfile";
        }
        {
          name = "VPN";
          description = "GlobalProtect VPN Client";
          packages = [
            pkgs.globalprotect-openconnect
            pkgs.openconnect
          ];
          icon = "yast-vpn";
          command = "gpclient -platform wayland";
          extraModules = [
            {
              imports = [
                ../services/globalprotect-vpn/default.nix
              ];

              ghaf.reference.services.globalprotect = {
                enable = true;
                csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
              };
            }
          ];
        }
        {
          name = "Video Editor";
          description = "Losslesscut Video Editor";
          packages = [ pkgs.losslesscut-bin ];
          icon = "losslesscut";
          command = "losslesscut --enable-features=UseOzonePlatform --ozone-platform=wayland";
        }
      ]
      ++ optionals (config.ghaf.profiles.graphics.compositor != "cosmic") [
        {
          name = "Text Editor";
          description = "Simple Text Editor";
          packages =
            let
              # Remove rounded corners from the text editor window
              gnomeTextEditor = pkgs.gnome-text-editor.overrideAttrs (oldAttrs: {
                postPatch = (oldAttrs.postPatch or "") + ''
                  echo -e '\nwindow { border-radius: 0px; }' >> src/style.css
                '';
              });
            in
            [
              gnomeTextEditor
              pkgs.adwaita-icon-theme
            ];
          icon = "org.gnome.TextEditor";
          command = "gnome-text-editor";
          extraModules = [
            {
              # Enable dconf for gnome text editor
              programs.dconf.enable = true;
            }
          ];
        }
        {
          name = "Xarchiver";
          description = "File Compressor";
          packages = [ pkgs.xarchiver ];
          icon = "xarchiver";
          command = "xarchiver";
        }
      ];
    extraModules = [
      {
        # Attach integrated camera to this vm
        microvm.devices = [ ];
        imports = [
          ../services/pac/pac.nix
          ../services/wireguard-gui/wireguard-gui.nix
        ];

        ghaf.firewall.extra =
          let
            # WARN: if all the traffic including VPN flowing through proxy is intended,
            # remove "151.253.154.18" rule and pass "--proxy-server=http://192.168.100.1:3128" to openconnect(VPN) app.
            # also remove "151.253.154.18,tii.ae,.tii.ae,sapsf.com,.sapsf.com" addresses from noProxy option and add
            # them to allow acl list in modules/reference/appvms/3proxy-config.nix file.
            vpnIpAddr = "151.253.154.18";
          in
          {
            input.filter = [
              # allow everything for local VPN traffic
              "-i tun0 -j ghaf-fw-conncheck-accept"
              "-p tcp -s ${vpnIpAddr} -m multiport --sports 80,443 -j ghaf-fw-conncheck-accept"
            ];

            output.filter = [
              "-p tcp -d ${vpnIpAddr} -m multiport --dports 80,443 -j ACCEPT"
              # Block HTTP and HTTPS if NOT going out via VPN
              "! -o tun0 -p tcp -m multiport --dports 80,443 -j nixos-fw-log-refuse"
              "! -o tun0 -p udp -m multiport --dports 80,443 -j nixos-fw-log-refuse"
            ];
          };
        # Enable Proxy Auto-Configuration service for the browser
        ghaf.reference.services = {
          pac = {
            enable = true;
            proxyAddress = config.ghaf.reference.services.proxy-server.internalAddress;
            proxyPort = config.ghaf.reference.services.proxy-server.bindPort;
          };

          # Enable WireGuard GUI
          wireguard-gui.enable = config.ghaf.reference.services.wireguard-gui;

        };

        # '--load-extension' flag is available only in non-Chrome branded Chromium
        # as of v137, with the only possible workaround removed in v139
        # refs:
        # https://groups.google.com/a/chromium.org/g/chromium-extensions/c/1-g8EFx2BBY/m/S0ET5wPjCAAJ
        # https://groups.google.com/a/chromium.org/g/chromium-extensions/c/FxMU1TvxWWg/m/daZVTYNlBQAJ
        #
        # Therefore we load the extension via 'ExtensionInstallForcelist' policy
        # A mock extension update server is needed for this to work
        # ref: https://chromeenterprise.google/policies/#ExtensionInstallForcelist
        systemd.services.chrome-extension-server = mkIf enableOpenNormalExtension {
          enable = true;
          description = "Local Chrome extension update server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            ExecStart = "${getExe pkgs.python3} -m http.server 8080 --directory ${pkgs.open-normal-extension}/share";
            WorkingDirectory = "${pkgs.open-normal-extension}/share";
            Restart = "always";
          };
        };
      }
    ];
  };
}
