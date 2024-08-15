# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.networking.hosts;
  inherit (lib)
    mkIf
    types
    mkOption
    optionals
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
  # Use to .101. (debug) to access guests from host.
  # debug network hosts are post-fixed: <hostname>-debug
  ipBase = "192.168.100";
  debugBase = "192.168.101";
  hostsEntries = [
    {
      ip = 1;
      name = "net-vm";
    }
    {
      ip = 2;
      name = "ghaf-host";
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
      name = "chromium-vm";
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
      name = "element-vm";
    }
    {
      ip = 104;
      name = "appflowy-vm";
    }
    {
      ip = 105;
      name = "business-vm";
    }
  ];

  mkHostEntryTxt =
    { ip, name }:
    "${ipBase}.${toString ip}\t${name}\n"
    + lib.optionalString config.ghaf.profiles.debug.enable "${debugBase}.${toString ip}\t${name}-debug\n";
  entriesTxt = map mkHostEntryTxt hostsEntries;

  mkHostEntry =
    { ip, name }:
    {
      name = "${name}";
      ip = "${ipBase}.${toString ip}";
    };
  mkHostEntryDebug =
    { ip, name }:
    {
      name = "${name}-debug";
      ip = "${debugBase}.${toString ip}";
    };
  entries =
    (map mkHostEntry hostsEntries)
    ++ optionals config.ghaf.profiles.debug.enable (map mkHostEntryDebug hostsEntries);
in
{
  options.ghaf.networking.hosts = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    entries = mkOption {
      type = types.listOf hostsEntrySubmodule;
      default = null;
    };
  };

  config = mkIf cfg.enable {
    ghaf.networking.hosts = {
      inherit entries;
    };

    # Generate hosts file
    environment.etc.hosts = lib.mkForce {
      text = lib.foldl' (acc: x: acc + x) "127.0.0.1 localhost\n" entriesTxt;
      mode = "0444";
    };
  };
}
