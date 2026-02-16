# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Business App VM - Trusted Browser, Microsoft Office Suite, VPN
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.business;
  policyDir = "/etc/policies";
  inherit (lib) optionals getExe;
  enableOpenNormalExtension = true;

  # Get VM config for proxy PAC URL
  vmConfig = lib.ghaf.vm.getConfig config.microvm.vms."business-vm";
  proxyPacUrl = vmConfig.ghaf.reference.services.pac.proxyPacUrl or "";

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
    ''
    + lib.optionalString enableOpenNormalExtension ''
      EXTENSIONS_FILTER='
        | .extensions |= . // {}
        | .extensions.pinned_extensions |= (. + ["${pkgs.chrome-extensions.open-normal.id}"] | unique)
      '
      JQ_FILTER="$JQ_FILTER $EXTENSIONS_FILTER"
    ''
    + ''
      debug "jq filter being applied:"
      debug "$JQ_FILTER"

      jq "$JQ_FILTER" "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"
      debug "Preferences updated successfully."

      # Launch the browser
      debug "Launching Chrome..."
      "$CHROME_BIN" --enable-features=UseOzonePlatform \
        --ozone-platform=wayland \
        --disable-gpu \
        --class=google-chrome-business \
        --hide-crash-restore-bubble \
        --no-first-run \
        ${config.ghaf.givc.idsExtraArgs} \
        --proxy-pac-url=${proxyPacUrl} "$@"
    '';
  };
in
{
  _file = ./business.nix;

  options.ghaf.reference.appvms.business = {
    enable = lib.mkEnableOption "Business App VM";
  };

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    # DRY: Only enable, evaluatedConfig, and usbPassthrough at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.business = {

      enable = lib.mkDefault true;

      usbPassthrough = [
        {
          description = "Internal Webcams for BusinessVM";
          targetVm = "business-vm";
          tag = "cam";
          allow = config.ghaf.reference.passthrough.usb.internalWebcams;
        }
      ];

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "business";
        packages = optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
        mem = 6144;
        vcpu = 4;
        borderColor = "#218838";
        ghafAudio.enable = lib.mkDefault true;
        vtpm.enable = lib.mkDefault true;
        yubiProxy = true;
        applications = [
          {
            name = "google-chrome-business";
            desktopName = "Trusted Browser";
            categories = [ "WebBrowser" ];
            description = "Isolated Trusted Browsing";
            packages = [ trustedBrowserWrapper ];
            icon = "thorium-browser";
            exec = "trusted-browser-wrapper";
            givcArgs = [ "url" ];
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

                      extensions = [
                        pkgs.chrome-extensions.session-buddy
                      ];
                    };
                    programs.chromium = {
                      enable = chromePackage == pkgs.chromium;
                      openInNormalExtension = enableOpenNormalExtension;
                    };
                  };

                  storagevm.maximumSize = 100 * 1024; # 100 GB space for business-vm

                  xdgitems.enable = lib.mkDefault true;
                  # Open external URLs locally in business-vm's browser instead of forwarding to a dedicated URL-handling VM
                  xdghandlers.url = true;
                  security.apparmor.enable = lib.mkDefault true;
                };
              }
            ];
          }
          {
            name = "chrome-outlook.office.com__mail_-Default";
            desktopName = "Microsoft Outlook";
            categories = [
              "Email"
              "Calendar"
            ];
            description = "Microsoft Email Client";
            icon = "ms-outlook";
            exec = "trusted-browser-wrapper --app=https://outlook.office.com/mail/";
          }
          {
            name = "chrome-microsoft365.com__-Default";
            desktopName = "Microsoft 365";
            categories = [ "Office" ];
            description = "Microsoft 365 Software Suite";
            icon = "microsoft-365";
            exec = "trusted-browser-wrapper --app=https://microsoft365.com";
          }
          {
            name = "chrome-teams.microsoft.com__-Default";
            desktopName = "Teams";
            description = "Microsoft Teams Collaboration Application";
            categories = [
              "Office"
              "VideoConference"
            ];
            icon = "teams-for-linux";
            exec = "trusted-browser-wrapper --app=https://teams.microsoft.com";
          }
          {
            name = "chrome-gala.atrc.azure-atrc.androidinthecloud.net__-Default";
            desktopName = "Gala";
            categories = [
              "Network"
              "Utility"
            ];
            description = "Secure Android-in-the-Cloud";
            icon = "distributor-logo-android";
            exec = "trusted-browser-wrapper --app=https://gala.atrc.azure-atrc.androidinthecloud.net/#/login";
          }
          {
            name = "VPN";
            desktopName = "VPN";
            description = "GlobalProtect VPN Client";
            categories = [
              "Network"
              "Settings"
            ];
            packages = [ pkgs.gp-gui ];
            icon = "yast-vpn";
            exec = "gp-gui";
            extraModules = [
              {
                imports = [ inputs.gp-gui.nixosModules.default ];
                programs.gp-gui.enable = lib.mkDefault true;
              }
            ];
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

            ghaf = {
              firewall.extra =
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

              # Enable Policy Client
              givc.policyClient = {
                enable = true;
                storePath = policyDir;
              };
              storagevm = {
                directories = [
                  {
                    directory = policyDir;
                    user = config.ghaf.users.appUser.name;
                    group = config.ghaf.users.appUser.name;
                    mode = "0774";
                  }
                ];
              };

              # Enable Proxy Auto-Configuration service for the browser
              reference.services = {
                pac = {
                  enable = lib.mkDefault true;
                  pacFileFetcher = {
                    enable = false;
                    proxyAddress = config.ghaf.reference.services.proxy-server.internalAddress;
                    proxyPort = config.ghaf.reference.services.proxy-server.bindPort;
                  };
                };

                # Enable WireGuard GUI
                wireguard-gui = {
                  enable = config.ghaf.reference.services.wireguard-gui;
                  serverPorts = [ 51821 ];
                };
              };

              development.debug.tools.av.enable = config.ghaf.profiles.debug.enable;
            };
          }
        ];
      };
    };
  };
}
