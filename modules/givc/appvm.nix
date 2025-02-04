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
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
in
{
  options.ghaf.givc.appvm = {
    enable = mkEnableOption "Enable appvm givc module.";
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
      inherit (config.ghaf.users.loginUser) uid;
      transport = {
        name = hostName;
        addr = hosts.${hostName}.ipv4;
        port = "9000";
      };
      inherit (cfg) applications;
      tls.enable = config.ghaf.givc.enableTls;
      admin = lib.head config.ghaf.givc.adminConfig.addresses;
    };
  };
}
