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
    ;
  mitmEnabled =
    config.ghaf.virtualization.microvm.idsvm.enable
    && config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable;
  mitmExtraArgs = lib.optionalString mitmEnabled "--user-data-dir=/home/${config.ghaf.users.appUser.name}/.config/google-chrome/Default --test-type --ignore-certificate-errors-spki-list=Bq49YmAq1CG6FuBzp8nsyRXumW7Dmkp7QQ/F82azxGU=";
in
{
  options.ghaf.givc = {
    enable = mkEnableOption "Enable gRPC inter-vm communication";
    debug = mkEnableOption "Enable givc debug mode";
    enableTls = mkOption {
      description = "Enable TLS for gRPC communication globally, or disable for debugging.";
      type = types.bool;
      default = false;
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
          addr = mkOption {
            description = "Address of admin server";
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
    };
  };
  config = mkIf cfg.enable {
    # Givc admin server configuration
    ghaf.givc.adminConfig =
      let
        adminvmEntry = builtins.filter (x: x.name == "admin-vm-debug") config.ghaf.networking.hosts.entries;
        addr = lib.head (builtins.map (x: x.ip) adminvmEntry);
      in
      {
        name = "admin-vm-debug";
        inherit addr;
        port = "9001";
        protocol = "tcp";
      };
  };
}
