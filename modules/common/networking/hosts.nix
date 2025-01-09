# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
args@{ config, lib, ... }:
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
  # Use to .101. (debug) to access guests from host.
  # debug network hosts are post-fixed: <hostname>-debug
  ipBase = "192.168.100";
  debugBase = "192.168.101";
  hostsEntries =
    [
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
    ]
    ++ lib.imap0
      (i: vm: {
        ip = 100 + i;
        name = vm.name + "-vm";
      })
      (
        let
          c = if config.networking.hostName == "ghaf-host" then config else args.configHost;
        in
        c.ghaf.virtualization.microvm.appvm.vms or [ ]
      );

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
  };

  config = mkIf cfg.enable {
    ghaf.networking.hosts = {
      inherit entries;
    };

    networking.hosts = foldr recursiveUpdate { } (
      map (vm: {
        "${vm.ip}" = [ "${vm.name}" ];
      }) config.ghaf.networking.hosts.entries
    );
  };
}
