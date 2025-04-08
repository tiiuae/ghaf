# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib }:

with lib;

types.submodule {
  options = {
    interfaceName = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Name of the network interface.";
    };
    name = mkOption {
      type = types.nullOr types.str;
      description = "Host name as string.";
      default = null;
    };
    mac = mkOption {
      type = types.nullOr types.str;
      description = "MAC address as string.";
      default = null;
    };
    ipv4 = mkOption {
      type = types.nullOr types.str;
      description = "IPv4 address as string.";
      default = null;
    };
    ipv6 = mkOption {
      type = types.nullOr types.str;
      description = "IPv6 address as string.";
      default = null;
    };
    ipv4SubnetPrefixLength = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "The IPv4 subnet prefix length (e.g. 24 for 255.255.255.0)";
      example = 24;
    };
  };
}
