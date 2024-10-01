# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.services.proxy-server;
  inherit (lib) mkEnableOption mkIf;
  # use nix-prefetch-url to calculate sha256 checksum
  # TODO The urls should be fetched during boot. The script should be implemented in netvm or adminvm
  #pkgs.fetchurl {
  #  url = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7";
  #  sha256 = "1zly0g23vray4wg6fjxxdys6zzksbymlzggbg75jxqcf8g9j6xnw";
  #};
  msEndpointsFile = ./ms_urls.json;
  # Read and parse the JSON file
  msEndpointsData = builtins.fromJSON (builtins.readFile msEndpointsFile);

  # Extract URLs from the JSON data based on categories
  msExtractUrls = map (x: x.urls or [ ]) (
    lib.filter (
      x: x.category == "Optimize" || x.category == "Allow" || x.category == "Default"
    ) msEndpointsData
  );

  msUrlsFlattened = builtins.concatLists msExtractUrls ++ [ "microsoft365.com" ];

  tiiUrls = [
    #for jira avatars
    "*.gravatar.com"
    # for confluence icons
    "*.atlassian.com"
    "*tii.ae"
    "*tii.org"
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
    "cache.vedenemo.dev"
    "vedenemo.dev"
    "loki.ghaflogs.vedenemo.dev"
    "ghaflogs.vedenemo.dev"
    "himalia.vedenemo.dev"
  ];
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
    assertions = [

    ];

    #Firewall Settings
    networking = {
      firewall.enable = true;
      firewall.extraCommands = ''
         # Allow incoming connections to 3proxy on port ${toString cfg.bindPort} from the client's IP
        iptables -I INPUT -p tcp -s 192.168.100.0/24 --dport ${toString cfg.bindPort} -j ACCEPT
        iptables -I INPUT -p udp -s 192.168.100.0/24 --dport ${toString cfg.bindPort} -j ACCEPT
      '';
    };
    services._3proxy = {
      enable = true;
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
              targets = msUrlsFlattened;
            }
            {
              rule = "allow";
              targets = tiiUrls;
            }
            {
              rule = "allow";
              targets = ssrcUrls;
            }
            { rule = "deny"; }
          ];
        }
      ];
    };

  };
}
