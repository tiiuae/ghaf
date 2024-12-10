# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

let
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
  # Create a lookup map from entries
  lookupMap = builtins.listToAttrs (
    map (entry: {
      inherit (entry) name;
      value = entry.ip;
    }) hostsEntries
  );

  # Function to find the corresponding IP address by name
  ipByName = name: lookupMap.${name};

in
{
  inherit ipByName;
  inherit hostsEntries;
}
