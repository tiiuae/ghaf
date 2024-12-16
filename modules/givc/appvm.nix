# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  ...
}:
let
  cfg = config.ghaf.givc.appvm;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;
  vmEntry = vm: builtins.filter (x: x.name == vm) config.ghaf.networking.hosts.entries;
  address = vm: lib.head (builtins.map (x: x.ip) (vmEntry vm));
in
{
  options.ghaf.givc.appvm = {
    enable = mkEnableOption "Enable appvm givc module.";
    name = mkOption {
      type = types.str;
      default = "appvm";
      description = "Name of the appvm.";
    };
    applications = mkOption {
      type = types.listOf types.attrs;
      default = [ { } ];
      description = "Applications to run in the appvm.";
    };
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure appvm service
    givc.appvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      agent = {
        inherit (cfg) name;
        addr = address cfg.name;
        port = "9000";
      };
      inherit (cfg) applications;
      tls.enable = config.ghaf.givc.enableTls;
      admin = config.ghaf.givc.adminConfig;
    };
  };
}
