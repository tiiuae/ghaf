# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.services.pac;
  proxyUserName = "proxy-user";
  proxyGroupName = "proxy-admin";
  pacFileName = "ghaf.pac";
  pacServerAddr = "127.0.0.1:8000";
  _ghafPacFileFetcher =
    let
      pacFileDownloadUrl = cfg.pacUrl;
      proxyServerUrl = "http://${cfg.proxyAddress}:${toString cfg.proxyPort}";
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
  options.ghaf.reference.services.pac = {
    enable = lib.mkEnableOption "Proxy Auto-Configuration (PAC)";

    proxyAddress = lib.mkOption {
      type = lib.types.str;
      description = "Proxy address";
    };

    proxyPort = lib.mkOption {
      type = lib.types.int;
      description = "Proxy port";
    };

    pacUrl = lib.mkOption {
      type = lib.types.str;
      description = "URL of the Proxy Auto-Configuration (PAC) file";
      default = "https://raw.githubusercontent.com/tiiuae/ghaf-rt-config/refs/heads/main/network/proxy/ghaf.pac";
    };

    proxyPacUrl = lib.mkOption {
      type = lib.types.str;
      description = "Local PAC URL that can be passed to the browser";
      default = "http://${pacServerAddr}/${pacFileName}";
      readOnly = true;
    };
  };

  config = lib.mkIf cfg.enable {
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

  };
}
