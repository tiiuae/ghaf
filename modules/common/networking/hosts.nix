# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib)
    foldr
    mkOption
    recursiveUpdate
    optionalString
    types
    trivial
    listToAttrs
    nameValuePair
    ;

  # Internal network host entry
  # TODO Add sockets
  hostEntrySubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          Host name as string.
        '';
      };
      mac = mkOption {
        type = types.str;
        description = ''
          MAC address as string.
        '';
      };
      ipv4 = mkOption {
        type = types.str;
        description = ''
          IPv4 address as string.
        '';
      };
      ipv6 = mkOption {
        type = types.str;
        description = ''
          IPv6 address as string.
        '';
      };
    };
  };

  # Re-order hosts to ensure net-vm is always first in list to reserve .1
  hostList = [
    "net-vm"
    "ghaf-host"
  ] ++ lib.lists.remove "net-vm" config.ghaf.common.systemHosts;

  # Address bases
  macBaseAddress = "02:AD:00:00:00:";
  ipv4BaseAddress = "192.168.100.";
  ipv6BaseAddress = "fd00::100:";

  # Generate host entries
  # TODO Add sockets
  hosts =
    lib.lists.imap1 (idx: name: {
      inherit name;
      mac = "${macBaseAddress}${optionalString (idx < 16) "0"}${trivial.toHexString idx}";
      ipv4 = "${ipv4BaseAddress}${toString idx}";
      ipv6 = "${ipv6BaseAddress}${toString idx}";
    }) hostList
    ++ lib.lists.imap1 (
      index: name:
      let
        idx = index + 100;
      in
      {
        inherit name;
        mac = "${macBaseAddress}${optionalString (idx < 16) "0"}${trivial.toHexString idx}";
        ipv4 = "${ipv4BaseAddress}${toString idx}";
        ipv6 = "${ipv6BaseAddress}${toString idx}";
      }
    ) config.ghaf.common.appHosts;
in
{
  options.ghaf.networking = {
    hosts = mkOption {
      type = types.attrsOf hostEntrySubmodule;
      description = ''
        List of hosts entries.
      '';
      default = null;
    };
  };

  config = {

    assertions = [
      {
        assertion = lib.length config.ghaf.common.vms < 255;
        message = "Too many VMs defined - maximum is 254";
      }
    ];

    ghaf.networking.hosts = listToAttrs (map (host: nameValuePair "${host.name}" host) hosts);

    networking.hosts = foldr recursiveUpdate { } (
      map (vm: {
        "${vm.ipv4}" = [ "${vm.name}" ];
      }) hosts
    );
  };
}
