# Copyright 2024 TII (SSRC) and the Ghaf contributors
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
  proxyAllowListName = "allowlist.txt";
  proxyWritableAllowListPath = "/etc/${proxyAllowListName}";
  ms-url-fetcher = pkgs.callPackage ./ms_url_fetcher.nix {
    allowListPath = proxyWritableAllowListPath;
  };

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
  tiiUrls = [
    #for jira avatars
    "*.gravatar.com"
    # for confluence icons
    "*.atlassian.com"
    "*tii.ae"
    "*tii.org"
    "tiiuae.sharepoint.com"
    "tiiuae-my.sharepoint.com"
    "hcm22.sapsf.com"
    "aderp.addigital.gov.ae"
    "s1.mn1.ariba.com"
    "tii.sourcing.mn1.ariba.com"
    "a1c7ohabl.accounts.ondemand.com"
    "flpnwc-ojffapwnic.dispatcher.ae1.hana.ondemand.com"
    "*.docusign.com"
    "access.clarivate.com"
  ];

  ssrcUrls = [
    "*.cachix.org"
    "vedenemo.dev"
    "loki.ghaflogs.vedenemo.dev"
    "ghaflogs.vedenemo.dev"
    "himalia.vedenemo.dev"
  ];

  extraMsUrls = [
    #ms366
    "graph.microsoft.com"
    "ocws.officeapps.live.com"
    "microsoft365.com"
    "*.azureedge.net" # microsoft365 icons
    "consentreceiverfd-prod.azurefd.net" # ms365 cookies
    "c.s-microsoft.com"
    "js.monitor.azure.com"
    "ocws.officeapps.live.com"
    "northcentralus0-mediap.svc.ms"
    "*.bing.com"
    "cdnjs.cloudfare.com"
    "store-images.s-microsoft.com"
    "www.office.com"
    "res-1.cdn.office.net"
    "secure.skypeassets.com"
    "js.live.net"
    "skyapi.onedrive.live.com"
    "am3pap006files.storage.live.com"
    "c7rr5q.am.files.1drv.com"
    #teams
    "teams.live.com"
    "*.teams.live.com"
    "fpt.live.com" # teams related
    "statics.teams.cdn.live.net"
    "ipv6.login.live.com"
    #outlook
    "outlook.live.com" # outlook login
    "csp.microsoft.com"
    "arc.msn.com"
    "www.msn.com"
    "outlook.com"
    #https://learn.microsoft.com/en-us/microsoft-365/enterprise/managing-office-365-endpoints?view=o365-worldwide#why-do-i-see-names-such-as-nsatcnet-or-akadnsnet-in-the-microsoft-domain-names
    "*.akadns.net"
    "*.akam.net"
    "*.akamai.com"
    "*.akamai.net"
    "*.akamaiedge.net"
    "*.akamaihd.net"
    "*.akamaized.net"
    "*.edgekey.net"
    "*.edgesuite.net"
    "*.nsatc.net"
    "*.exacttarget.com"
    #onedrive
    "1drv.ms"
    "onedrive.live.com"
    "p.sfx.ms"
    "my.microsoftpersonalcontent.com"
    "*.onedrive.com"
    "cdn.onenote.net"
  ];
  # Concatenate the lists and join with commas
  concatenatedUrls = builtins.concatStringsSep "," (tiiUrls ++ ssrcUrls ++ extraMsUrls);

  config_file_content = ''
    # log to stdout
    log

    nscache 65535
    nscache6 65535

    auth iponly
    #private addresses
    deny * * 0.0.0.0/8,127.0.0.0/8,10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16,::,::1,fc00::/7

    allow * * ${concatenatedUrls} *
    #include dynamic whitelist ips
    include "${proxyWritableAllowListPath}"

    deny * * * *
    maxconn 200

    proxy -i${netvmAddr} -p${toString cfg.bindPort}

    flush

  '';

  netvmEntry = builtins.filter (x: x.name == "net-vm") config.ghaf.networking.hosts.entries;
  netvmAddr = lib.head (builtins.map (x: x.ip) netvmEntry);
in
{
  options.ghaf.reference.services.proxy-server = {
    enable = mkEnableOption "Enable proxy server module";
    bindPort = lib.mkOption {
      type = lib.types.int;
      default = 3128;
      description = "Bind port for proxy server";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      [
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

    # Set up the permissions for allowlist.txt
    environment.etc."${proxyAllowListName}" = {
      text = '''';
      user = "${proxyUserName}"; # Owner is proxy-user
      group = "${proxyGroupName}"; # Group is proxy-admin
      mode = "0660"; # Permissions: read/write for owner/group, no permissions for others
    };

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

    environment.systemPackages = [ ms-url-fetcher ];
    #Firewall Settings
    networking = {
      firewall.enable = true;
      firewall.extraCommands = ''
         # Allow incoming connections to 3proxy on port ${toString cfg.bindPort} from the client's IP
        iptables -I INPUT -p tcp -s 192.168.100.0/24 --dport ${toString cfg.bindPort} -j ACCEPT
        iptables -I INPUT -p udp -s 192.168.100.0/24 --dport ${toString cfg.bindPort} -j ACCEPT
      '';
    };
    # systemd service for fetching the file
    systemd.services.fetchFile = {
      description = "Fetch a file periodically with retries if internet is available";

      serviceConfig = {
        ExecStart = "${ms-url-fetcher}/bin/ms-url-fetch";
        # Ensure fetchFile starts after the network is up
        Type = "simple";
        # Retry until systemctl restart 3proxy succeeds
        ExecStartPost = "${_3proxy-restart}/bin/3proxy-restart";
        # Restart policy on failure
        Restart = "on-failure"; # Restart the service if it fails
        RestartSec = "10s"; # Wait 10 seconds before restarting
        User = "${proxyUserName}";
      };
    };

    # systemd timer to trigger the service every 10 minutes
    systemd.timers.fetchFile = {
      description = "Run fetch-file periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        User = "${proxyUserName}";
        Persistent = true; # Ensures the timer runs after a system reboot
        OnCalendar = "hourly"; # Set to your desired schedule
        OnBootSec = "60s";
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

      /*
        NOTE allow and deny configurations should must be placed before the other configs
        it is not possible to do with extraConfig. Because it appends the file
      */
      /*
            services = [
              {
                type = "proxy";
                bindAddress = "${netvmAddr}";
                inherit (cfg) bindPort;
                maxConnections = 200;
                auth = [ "iponly" ];
                acl = [
                  {
                    rule = "allow";
                    targets = tiiUrls;
                  }
                  {
                    rule = "allow";
                    targets = ssrcUrls;
                  }
                   {
                    rule = "allow";
                    targets = extraMsUrls;
                  }
                  { rule = "deny"; }
                ];
              }
            ];
      */
    };

  };
}
