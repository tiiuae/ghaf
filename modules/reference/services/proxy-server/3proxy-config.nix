# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.services.proxy-server;
  inherit (lib) mkEnableOption mkIf;
  proxyUserName = "proxy-user";
  proxyGroupName = "proxy-admin";
  url-fetcher = pkgs.callPackage ./url_fetcher.nix { };

  msUrls = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7";
  ghafUrls = "https://api.github.com/repos/tiiuae/ghaf-rt-config/contents/network/proxy/urls?ref=main";

  msAllowFilePath = "3proxy/ms_whitelist.txt";
  ghafAllowFilePath = "3proxy/ghaf_whitelist.txt";

  allowListPaths = [
    msAllowFilePath
    ghafAllowFilePath
  ];

  _3proxy-restart = pkgs.writeShellApplication {
    name = "3proxy-restart";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils # Provides 'sleep' and other basic utilities
    ];
    text = ''

      sleep 2
      systemctl stop 3proxy.service
      echo "Attempting to start 3proxy service"

      # Retry loop for systemctl start 3proxy.service
      while ! systemctl is-active --quiet 3proxy.service; do
        echo "3proxy is not activated, retrying to start in 5 seconds..."
        systemctl start 3proxy.service
        sleep 5
      done

      echo "3proxy service successfully started"
    '';
  };

  config_file_content = ''
    # log to stdout
    log

    nscache 65535
    nscache6 65535

    auth iponly
    #private addresses
    deny * * 0.0.0.0/8,127.0.0.0/8,10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16,::,::1,fc00::/7

    #include dynamic whitelist ips
    include "/etc/${msAllowFilePath}"
    include "/etc/${ghafAllowFilePath}"

    deny * * * *
    maxconn 200

    proxy -i${cfg.internalAddress} -p${toString cfg.bindPort}

    flush

  '';
in
{
  _file = ./3proxy-config.nix;

  options.ghaf.reference.services.proxy-server = {
    enable = mkEnableOption "Enable proxy server module";
    internalAddress = lib.mkOption {
      type = lib.types.str;
      default = config.ghaf.networking.hosts."net-vm".ipv4;
      description = "Internal address for proxy server";
    };
    bindPort = lib.mkOption {
      type = lib.types.int;
      default = 3128;
      description = "Bind port for proxy server";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
    ];
    # Define a new group for proxy management
    users.groups.${proxyGroupName} = { }; # Create a group named proxy-admin

    # Define a new user with a specific username
    users.users.${proxyUserName} = {
      isSystemUser = true;
      description = "Proxy User for managing allowlist and services";
      # extraGroups = [ "${proxyGroupName}" ]; # Adding to 'proxy-admin' for specific access
      group = "${proxyGroupName}";
    };

    # Apply the configurations for each allow list path
    # Allow proxy-admin group to manage specific systemd services without a password
    security = {
      polkit = {
        enable = true;
        debug = true;
        # Polkit rules for allowing proxy-user to run proxy related systemctl
        # commands without sudo and password requirement
        extraConfig = ''
          polkit.addRule(function(action, subject) {
              if ((action.id == "org.freedesktop.systemd1.manage-units" &&
                   (action.lookup("unit") == "fetchFile.service" ||
                    action.lookup("unit") == "fetchFile.timer" ||
                    action.lookup("unit") == "3proxy.service")) &&
                  subject.user == "${proxyUserName}") {
                  return polkit.Result.YES;
              }
          });
        '';
      };

    };

    environment.systemPackages = [ url-fetcher ];
    #Firewall Settings
    ghaf.firewall.extra.input.filter = [
      # Allow incoming connections to 3proxy on port ${toString cfg.bindPort} from the client's IP
      "-p tcp -s 192.168.100.0/24 --dport ${toString cfg.bindPort} -j ghaf-fw-conncheck-accept"
      "-p udp -s 192.168.100.0/24 --dport ${toString cfg.bindPort} -j ghaf-fw-conncheck-accept"
    ];

    # Apply the allowListConfig generated from the list
    systemd = {
      tmpfiles.rules = map (
        tmpPath: "f /etc/${tmpPath} 0660 ${proxyUserName} ${proxyGroupName} - -"
      ) allowListPaths;

      # systemd service for fetching the file
      services.msFetchUrl = {
        description = "Fetch microsoft URLs periodically with retries if internet is available";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = "${url-fetcher}/bin/url-fetcher -u ${msUrls} -p /etc/${msAllowFilePath}";
          # Ensure msFetchUrl starts after the network is up
          Type = "simple";
          # Retry until systemctl restart 3proxy succeeds
          ExecStartPost = "${_3proxy-restart}/bin/3proxy-restart";
          # Restart policy on failure
          Restart = "on-failure"; # Restart the service if it fails
          RestartSec = "10s"; # Wait 10 seconds before restarting
          User = "${proxyUserName}";
          Group = "${proxyGroupName}";

        };
      };

      # systemd timer to trigger the service every 10 minutes
      timers.msFetchUrl = {
        description = "Run msFetchUrl periodically";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          User = "${proxyUserName}";
          Persistent = true; # Ensures the timer runs after a system reboot
          OnCalendar = "hourly"; # Set to your desired schedule
          OnBootSec = "60s";
        };
      };
    };

    # systemd service for fetching the file
    systemd.services.ghafFetchUrl = {
      description = "Fetch ghaf related URLs periodically with retries if internet is available";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${url-fetcher}/bin/url-fetcher -f ${ghafUrls} -p /etc/${ghafAllowFilePath}";
        # Ensure ghafFetchUrl starts after the network is up
        Type = "simple";
        # Retry until systemctl restart 3proxy succeeds
        ExecStartPost = "${_3proxy-restart}/bin/3proxy-restart";
        # Restart policy on failure
        Restart = "on-failure"; # Restart the service if it fails
        RestartSec = "15s"; # Wait 15 seconds before restarting
        User = "${proxyUserName}";
        Group = "${proxyGroupName}";

      };
    };

    # systemd timer to trigger the service every 10 minutes
    systemd.timers.ghafFetchUrl = {
      description = "Run ghafFetchUrl periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        User = "${proxyUserName}";
        Group = "${proxyGroupName}";

        Persistent = true; # Ensures the timer runs after a system reboot
        OnCalendar = "hourly"; # Set to your desired schedule
        OnBootSec = "90s";
      };
    };

    systemd.services."3proxy".serviceConfig = {
      RestartSec = "5s";
      User = "${proxyUserName}";
      Group = "${proxyGroupName}";
    };

    services._3proxy = {
      enable = true;
      # Prepend the 'include' directive before the rest of the configuration
      confFile = pkgs.writeText "3proxy.conf" ''
        ${config_file_content}
      '';
    };

  };
}
