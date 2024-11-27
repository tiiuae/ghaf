# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    head
    filter
    ;
  name = "admin-vm";
  mitmEnabled =
    config.ghaf.virtualization.microvm.idsvm.enable
    && config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable;
  mitmExtraArgs = lib.optionalString mitmEnabled "--user-data-dir=/home/${config.ghaf.users.accounts.user}/.config/google-chrome/Default --test-type --ignore-certificate-errors-spki-list=Bq49YmAq1CG6FuBzp8nsyRXumW7Dmkp7QQ/F82azxGU=";
  getIp =
    name: head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.entries));
  getIpDebug =
    name: head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.debugEntries));
  addressSubmodule = types.submodule {
    options = {
      name = mkOption {
        description = "Name of the IP range for parsing";
        type = types.str;
      };
      addr = mkOption {
        description = "IP address of admin server";
        type = types.str;
      };
      port = mkOption {
        description = "Port of admin server";
        type = types.str;
      };
      protocol = mkOption {
        description = "Protocol of admin server";
        type = types.str;
      };
    };
  };
in
{
  options.ghaf.givc = {
    enable = mkEnableOption "Enable gRPC inter-vm communication";
    debug = mkEnableOption "Enable givc debug mode";
    enableTls = mkOption {
      description = "Enable TLS for gRPC communication globally, or disable for debugging.";
      type = types.bool;
      default = true;
    };
    idsExtraArgs = mkOption {
      description = "Extra arguments for applications when IDS/MITM is enabled.";
      type = types.str;
      default = mitmExtraArgs;
    };
    appPrefix = mkOption {
      description = "Common application path prefix.";
      type = types.str;
      default = "/run/current-system/sw/bin";
    };
    adminConfig = mkOption {
      description = "Admin server configuration.";
      type = types.submodule {
        options = {
          name = mkOption {
            description = "Host name of admin server";
            type = types.str;
          };
          addresses = mkOption {
            description = "Addresses of admin server";
            type = types.listOf addressSubmodule;
          };
        };
      };
    };
  };
  config = mkIf cfg.enable {
    # Givc admin server configuration
    ghaf.givc.adminConfig = {
      inherit name;
      addresses = [
        {
          inherit name;
          addr = getIp name;
          port = "9001";
          protocol = "tcp";
        }
        {
          inherit name;
          addr = getIpDebug name;
          port = "9001";
          protocol = "tcp";
        }
      ];
    };
  };
}
