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
  inherit (lib) mkIf optionalString;
  #TODO: Move this to a common place
  name = "business";
  proxyUserName = "proxy-user";
  proxyGroupName = "proxy-admin";
  tiiVpnAddr = "151.253.154.18";
  pacFileName = "ghaf.pac";
  pacServerAddr = "127.0.0.1:8000";
  pacFileUrl = "http://${pacServerAddr}/${pacFileName}";
  netvmEntry = builtins.filter (x: x.name == "net-vm") config.ghaf.networking.hosts.entries;
  netvmAddress = lib.head (builtins.map (x: x.ip) netvmEntry);
  # Remove rounded corners from the text editor window
  gnomeTextEditor = pkgs.gnome-text-editor.overrideAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + ''
        echo -e '\nwindow { border-radius: 0px; }' >> src/style.css
      '';
  });

  _ghafPacFileFetcher =
    let
      pacFileDownloadUrl = "https://raw.githubusercontent.com/tiiuae/ghaf-rt-config/refs/heads/main/network/proxy/ghaf.pac";
      proxyServerUrl = "http://${netvmAddress}:${toString config.ghaf.reference.services.proxy-server.bindPort}";
      logTag = "ghaf-pac-fetcher";
    in
    pkgs.writeShellApplication {
      name = "ghafPacFileFetcher";
      runtimeInputs = [
        pkgs.coreutils # Provides 'mv', 'rm', etc.
        pkgs.curl # For downloading PAC files
        pkgs.inetutils # Provides 'logger'
      ];
      text = ''
          # Variables
          TEMP_PAC_PATH=$(mktemp)       
          LOCAL_PAC_PATH="/etc/proxy/${pacFileName}"  

          # Logging function with timestamp
          log() {
              logger -t "${logTag}" "$1"
          }

          log "Starting the pac file fetch process..."

          # Fetch the pac file using curl with a proxy
          log "Fetching pac file from ${pacFileDownloadUrl} using proxy ${proxyServerUrl}..."
          http_status=$(curl --proxy "${proxyServerUrl}" -s -o "$TEMP_PAC_PATH" -w "%{http_code}" "${pacFileDownloadUrl}")

          log "HTTP status code: $http_status"

          # Check if the fetch was successful
          if [[ "$http_status" -ne 200 ]]; then
              log "Error: Failed to download pac file from ${pacFileDownloadUrl}. HTTP status code: $http_status"
              rm -f "$TEMP_PAC_PATH"  # Clean up temporary file
              exit 2
          fi

          # Verify the downloaded file is not empty
          if [[ ! -s "$TEMP_PAC_PATH" ]]; then
              log "Error: The downloaded pac file is empty."
              rm -f "$TEMP_PAC_PATH"  # Clean up temporary file
              exit 3
          fi

          # Log the download success
          log "Pac file downloaded successfully. Proceeding with update..."

          # Copy the content from the temporary pac file to the target file
          log "Copying the content from temporary file to the target pac file at $LOCAL_PAC_PATH..."

          # Check if the copy was successful
        if cat "$TEMP_PAC_PATH" > "$LOCAL_PAC_PATH"; then
              log "Pac file successfully updated at $LOCAL_PAC_PATH."
          else
              log "Error: Failed to update the pac file at $LOCAL_PAC_PATH."
              rm -f "$TEMP_PAC_PATH"  # Clean up temporary file
              exit 4
          fi

          # Clean up temporary file
          rm -f "$TEMP_PAC_PATH"

          log "Pac file fetch and update process completed successfully."
          exit 0
      '';
    };

in
{
  name = "${name}";
  packages =
    [
      pkgs.google-chrome
      pkgs.globalprotect-openconnect
      pkgs.losslesscut-bin
      pkgs.openconnect
      gnomeTextEditor
      pkgs.xarchiver
      pkgs.busybox
    ]
    ++ lib.optionals config.ghaf.profiles.debug.enable [ pkgs.tcpdump ]
    ++ lib.optionals config.ghaf.givc.enable [ pkgs.open-normal-extension ];

  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:10:01";
  ramMb = 6144;
  cores = 4;
  extraModules = [
    (
      { pkgs, ... }:
      {
        imports = [
          #    ../programs/chromium.nix
          ../programs/google-chrome.nix
          ../services/globalprotect-vpn/default.nix
        ];
        time.timeZone = config.time.timeZone;

        microvm = {
          qemu.extraArgs = lib.optionals (
            config.ghaf.hardware.usb.internal.enable
            && (lib.hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
          ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
          devices = [ ];
        };

        ghaf = {
          givc.appvm = {
            enable = true;
            name = lib.mkForce "business-vm";
            applications = [
              {
                name = "google-chrome";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --proxy-pac-url=${pacFileUrl} --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
                args = [ "url" ];
              }
              {
                name = "outlook";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --proxy-pac-url=${pacFileUrl} --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://outlook.office.com/mail/ ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
              }
              {
                name = "office";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --proxy-pac-url=${pacFileUrl} --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://microsoft365.com ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
              }
              {
                name = "teams";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --proxy-pac-url=${pacFileUrl} --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://teams.microsoft.com ${config.ghaf.givc.idsExtraArgs} --load-extension=${pkgs.open-normal-extension}";
              }
              {
                name = "gpclient";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gpclient -platform wayland";
              }
              {
                name = "gnome-text-editor";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/gnome-text-editor";
              }
              {
                name = "losslesscut";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/losslesscut --enable-features=UseOzonePlatform --ozone-platform=wayland";
              }
              {
                name = "xarchiver";
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/xarchiver";
              }
            ];
          };

          reference = {
            programs.google-chrome.enable = true;
            services.globalprotect = {
              enable = true;
              csdWrapper = "${pkgs.openconnect}/libexec/openconnect/hipreport.sh";
            };
          };

          services.xdghandlers.enable = true;
        };
        environment.etc."opt/chrome/native-messaging-hosts/fi.ssrc.open_normal.json" =
          mkIf config.ghaf.givc.enable
            {
              source = "${pkgs.open-normal-extension}/fi.ssrc.open_normal.json";
            };

        #   environment.etc."chromium/native-messaging-hosts/fi.ssrc.open_normal.json" =
        #     mkIf config.ghaf.givc.enable
        #       {
        #         source = "${pkgs.open-normal-extension}/fi.ssrc.open_normal.json";
        #       };
        environment.etc."open-normal-extension.cfg" = mkIf config.ghaf.givc.enable {
          text =
            let
              cliArgs = builtins.replaceStrings [ "\n" ] [ " " ] ''
                --name ${config.ghaf.givc.adminConfig.name}
                --addr ${config.ghaf.givc.adminConfig.addr}
                --port ${config.ghaf.givc.adminConfig.port}
                ${optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
                ${optionalString config.ghaf.givc.enableTls "--cert /run/givc/business-vm-cert.pem"}
                ${optionalString config.ghaf.givc.enableTls "--key /run/givc/business-vm-key.pem"}
                ${optionalString (!config.ghaf.givc.enableTls) "--notls"}
              '';
            in
            ''
              export GIVC_PATH="${pkgs.givc-cli}"
              export GIVC_OPTS="${cliArgs}"
            '';
        };

        # Enable dconf and icon pack for gnome text editor
        programs.dconf.enable = true;
        environment.systemPackages = [ pkgs.adwaita-icon-theme ];
        # Define a new group for proxy management
        users.groups.${proxyGroupName} = { }; # Create a group named proxy-admin

        # Define a new user with a specific username
        users.users.${proxyUserName} = {
          isSystemUser = true;
          description = "Proxy User for managing allowlist and services";
          # extraGroups = [ "${proxyGroupName}" ]; # Adding to 'proxy-admin' for specific access     
          group = "${proxyGroupName}";
        };

        environment.etc."proxy/${pacFileName}" = {
          text = '''';
          user = "${proxyUserName}"; # Owner is proxy-user
          group = "${proxyGroupName}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };

        systemd.services.pacServer = {
          description = "Http server to make PAC file accessible for web browsers";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.busybox}/bin/busybox httpd -f -p ${pacServerAddr} -h /etc/proxy";
            # Ensure ghafFetchUrl starts after the network is up
            Type = "simple";
            # Restart policy on failure
            Restart = "always"; # Restart the service if it fails
            RestartSec = "15s"; # Wait 15 seconds before restarting
            User = "${proxyUserName}";
          };
        };

        systemd.services.ghafPacFileFetcher = {
          description = "Fetch ghaf pac file periodically with retries if internet is available";

          serviceConfig = {
            ExecStart = "${_ghafPacFileFetcher}/bin/ghafPacFileFetcher";
            # Ensure ghafFetchUrl starts after the network is up
            Type = "simple";
            # Restart policy on failure
            Restart = "on-failure"; # Restart the service if it fails
            RestartSec = "15s"; # Wait 15 seconds before restarting
            User = "${proxyUserName}";
          };
        };

        systemd.timers.ghafPacFileFetcher = {
          description = "Run ghafPacFileFetcher periodically";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            User = "${proxyUserName}";
            Persistent = true; # Ensures the timer runs after a system reboot
            OnCalendar = "daily"; # Set to your desired schedule
            OnBootSec = "90s";
          };
        };

        #Firewall Settings
        networking = {
          firewall = {
            enable = true;
            extraCommands = ''

              add_rule() {
                    local ip=$1
                    iptables -I OUTPUT -p tcp -d $ip --dport 80 -j ACCEPT
                    iptables -I OUTPUT -p tcp -d $ip --dport 443 -j ACCEPT
                    iptables -I INPUT -p tcp -s $ip --sport 80 -j ACCEPT
                    iptables -I INPUT -p tcp -s $ip --sport 443 -j ACCEPT
                  }
              # Default policy
              iptables -P INPUT DROP

              iptables -A INPUT -i lo -j ACCEPT
              iptables -A OUTPUT -o lo -j ACCEPT

              # Block any other unwanted traffic (optional)
              iptables -N logreject
              iptables -A logreject -j LOG
              iptables -A logreject -j REJECT

              # allow everything for local VPN traffic
              iptables -A INPUT -i tun0 -j ACCEPT
              iptables -A FORWARD -i tun0 -j ACCEPT
              iptables -A FORWARD -o tun0 -j ACCEPT
              iptables -A OUTPUT -o tun0 -j ACCEPT

              # WARN: if all the traffic including VPN flowing through proxy is intended,
              # remove "add_rule 151.253.154.18" rule and pass "--proxy-server=http://192.168.100.1:3128" to openconnect(VPN) app.
              # also remove "151.253.154.18,tii.ae,.tii.ae,sapsf.com,.sapsf.com" addresses from noProxy option and add
              # them to allow acl list in modules/reference/appvms/3proxy-config.nix file.
              # Allow VPN access.tii.ae
              add_rule ${tiiVpnAddr}

              # Block all other HTTP and HTTPS traffic
              iptables -A OUTPUT -p tcp --dport 80 -j logreject
              iptables -A OUTPUT -p tcp --dport 443 -j logreject
              iptables -A OUTPUT -p udp --dport 80 -j logreject
              iptables -A OUTPUT -p udp --dport 443 -j logreject

            '';
          };
        };
      }
    )
  ];
  borderColor = "#218838";
  ghafAudio.enable = true;
  vtpm.enable = true;
}
