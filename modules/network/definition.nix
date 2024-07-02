# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Network Definitions
#
# The point of this module is to only store information about the network
# configuration, and the logic that uses this information should be elsewhere.
{lib, ...}: let
  inherit (lib) mkOption types literalExpression;
in {
  options.ghaf.network.definition = let
    networkSubmodule = types.submodule {
      options = {
        hostName = mkOption {
          type = types.str;
          description = ''
            Hostname
          '';
        };
        macAddress = mkOption {
          type = types.str;
          description = ''
            MAC address
          '';
        };
        ipAddressId = mkOption {
          type = types.int;
          description = ''
            IP Address ID, the last octet of internal/debug network IP address
          '';
        };
      };
    };
  in {
    internalNetwork = mkOption {
      description = "Internal network address";
      type = types.str;
      default = "192.168.100.0";
    };

    debugNetwork = mkOption {
      description = "Debug network address";
      type = types.str;
      default = "192.168.101.0";
    };

    virtualMachines = mkOption {
      description = "Virtual Machines";
      type = types.listOf networkSubmodule;
      default = [];
      example = literalExpression ''
        [{
          hostName = "net-vm";
          macAddress = "02:00:00:01:01:01";
          ipAddressId = 1;
        }]
      '';
    };
  };
}
