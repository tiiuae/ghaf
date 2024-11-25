# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.networking.hosts;
  inherit (lib)
    foldr
    mkIf
    mkOption
    optionals
    recursiveUpdate
    types
    ;

  hostsEntrySubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          Host name as string.
        '';
      };
      ip = mkOption {
        type = types.str;
        description = ''
          Host IPv4 address as string.
        '';
      };
    };
  };

  # please note that .100. network is not
  # reachable from ghaf-host. It's only reachable
  # guest-to-guest.
  network = "192.168.100";
  hostsEntries = [
    {
      ip = 1;
      name = "net-vm";
    }
    {
      ip = 3;
      name = "gui-vm";
    }
    {
      ip = 4;
      name = "ids-vm";
    }
    {
      ip = 5;
      name = "audio-vm";
    }
    {
      ip = 10;
      name = "admin-vm";
    }
    {
      ip = 100;
      name = "chrome-vm";
    }
    {
      ip = 101;
      name = "gala-vm";
    }
    {
      ip = 102;
      name = "zathura-vm";
    }
    {
      ip = 103;
      name = "comms-vm";
    }
    {
      ip = 104;
      name = "business-vm";
    }
  ];

  # Use to .101. (debug) to access guests from host. You have to hop over net-vm.
  # Debug network hosts are post-fixed: <hostname>-debug
  debugNetwork = "192.168.101";
  hostsDebugEntries = [
    {
      ip = 1;
      name = "net-vm";
    }
    {
      ip = 2;
      name = "ghaf-host";
    }
    {
      ip = 10;
      name = "admin-vm";
    }
  ];

  mkHostEntry =
    ipBase:
    { ip, name }:
    {
      name = "${name}";
      ip = "${ipBase}.${toString ip}";
    };

  entries = map (mkHostEntry network) hostsEntries;
  debugEntries = optionals config.ghaf.profiles.debug.enable (
    map (mkHostEntry debugNetwork) hostsDebugEntries
  );
in
{
  options.ghaf.networking.hosts = {
    enable = (lib.mkEnableOption "Ghaf hosts entries") // {
      default = true;
    };
    entries = mkOption {
      type = types.listOf hostsEntrySubmodule;
      description = ''
        List of hosts entries.
      '';
      default = null;
    };
    debugEntries = mkOption {
      type = types.listOf hostsEntrySubmodule;
      description = ''
        List of hosts entries for the debug network.
      '';
      default = null;
    };
  };

  config = mkIf cfg.enable {
    ghaf.networking.hosts = {
      inherit entries;
      inherit debugEntries;
    };

    networking.hosts = foldr recursiveUpdate { } (
      map (vm: {
        "${vm.ip}" = [ "${vm.name}" ];
      }) (config.ghaf.networking.hosts.entries ++ config.ghaf.networking.hosts.debugEntries)
    );
  };
}
