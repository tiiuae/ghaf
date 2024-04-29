# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
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
  ];
  mkHostEntry = {
    ip,
    name,
  }:
    "${ipBase}.${toString ip}\t${name}\n"
    + lib.optionalString config.ghaf.profiles.debug.enable
    "${debugBase}.${toString ip}\t${name}-debug\n";
  entries = map mkHostEntry hostsEntries;
in {
  environment.etc.hosts = lib.mkForce {
    text = lib.foldl' (acc: x: acc + x) "127.0.0.1 localhost\n" entries;
    mode = "0444";
  };
}
