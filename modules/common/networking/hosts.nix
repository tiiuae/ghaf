# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    nameValuePair
    ;

  # Re-order hosts to ensure net-vm is always first in list to reserve .1
  hostList = [
    "net-vm"
    "ghaf-host"
  ]
  ++ lib.lists.remove "net-vm" (
    config.ghaf.common.systemHosts ++ (builtins.filter (a: a != null) [ config.ghaf.common.adminHost ])
  );

  # Address bases
  macBaseAddress = "02:AD:00:00:00:";
  ipv4BaseAddress = "192.168.100.";
  ipv6BaseAddress = "fd00::100:";

  # Generate host entries
  generatedHosts =
    lib.lists.imap1 (idx: name: {
      inherit name;
      mac = "${macBaseAddress}${optionalString (idx < 16) "0"}${trivial.toHexString idx}";
      ipv4 = "${ipv4BaseAddress}${toString idx}";
      ipv6 = "${ipv6BaseAddress}${toString idx}";
      cid = if name == "net-vm" then (lib.length hostList) + 1 else idx;
      ipv4SubnetPrefixLength = 24;
      interfaceName = "ethint0";
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
        cid = idx;
        ipv4SubnetPrefixLength = 24;
        interfaceName = "ethint0";
      }
    ) config.ghaf.common.appHosts;

  # Evaluate generated hosts as attrset
  generatedHostAttrs = lib.listToAttrs (map (host: nameValuePair host.name host) generatedHosts);
  # Extract names of all extra hosts
  extraHostNames = lib.attrNames config.ghaf.common.extraNetworking.hosts;

  # Merge logic per host
  mergedExtraHosts = lib.listToAttrs (
    map (
      name:
      let
        gen = generatedHostAttrs.${name};
        extra = config.ghaf.common.extraNetworking.hosts.${name};
      in
      nameValuePair name {
        inherit name;
        mac = if extra ? mac && extra.mac != null then extra.mac else gen.mac;
        ipv4 = if extra ? ipv4 && extra.ipv4 != null then extra.ipv4 else gen.ipv4;
        ipv6 = if extra ? ipv6 && extra.ipv6 != null then extra.ipv6 else gen.ipv6;
        ipv4SubnetPrefixLength =
          if extra ? ipv4SubnetPrefixLength && extra.ipv4SubnetPrefixLength != null then
            extra.ipv4SubnetPrefixLength
          else
            gen.ipv4SubnetPrefixLength;
        interfaceName =
          if extra ? interfaceName && extra.interfaceName != null then
            extra.interfaceName
          else
            gen.interfaceName;

        inherit (gen) cid;
      }
    ) extraHostNames
  );

  # Combine generated and extra hosts (extra overrides or extends)
  combinedHosts = generatedHostAttrs // mergedExtraHosts;

  # networking.hosts derived from merged host entries
  networkingHosts = foldr recursiveUpdate { } (
    map (host: {
      "${host.ipv4}" = [ host.name ];
    }) (lib.attrValues combinedHosts)
  );
  # Extract values to check for uniqueness
  allHosts = lib.attrValues combinedHosts;
  getField = field: map (h: h.${field}) allHosts;

  checkUnique =
    field:
    let
      values = getField field;
      unique = lib.lists.unique values;

      # Find duplicates by filtering values that occur more than once
      duplicates = lib.lists.filter (
        value: lib.lists.length (lib.lists.filter (x: x == value) values) > 1
      ) unique;

      # Create a list of duplicates with the corresponding host names
      duplicateNames = lib.lists.filter (
        host: lib.lists.length (lib.lists.filter (x: x == host.${field}) values) > 1
      ) allHosts;

    in
    {
      inherit field;
      ok = values == unique;
      inherit duplicates;
      # Extract host names for duplicates
      duplicateNames = map (host: host.name) duplicateNames;
    };

  uniquenessChecks = map checkUnique [
    "mac"
    "ipv4"
    "ipv6"
    "cid"
    "name"
  ];

  uniquenessAssertions = map (check: {
    assertion = check.ok;
    message = "Duplicate ${check.field} values detected: ${lib.concatStringsSep ", " check.duplicates}, conflict between:${lib.concatStringsSep ", " check.duplicateNames}";

  }) uniquenessChecks;
in
{
  _file = ./hosts.nix;

  options.ghaf.networking = {
    hosts = mkOption {
      type = types.attrsOf types.networking;
      description = "List of hosts entries.";
      default = { };
    };

  };

  config = {
    assertions = [
      {
        assertion = lib.length config.ghaf.common.vms < 255;
        message = "Too many VMs defined - maximum is 254";
      }
    ]
    ++ uniquenessAssertions;

    ghaf.networking.hosts = combinedHosts;

    networking.hosts = networkingHosts;
  };
}
