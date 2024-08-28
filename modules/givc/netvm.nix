# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  ...
}:
let
  cfg = config.ghaf.givc.netvm;
  inherit (lib) mkEnableOption mkIf;
  hostName = "net-vm";
in
{
  options.ghaf.givc.netvm = {
    enable = mkEnableOption "Enable netvm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure netvm service
    givc.sysvm =
      let
        netvmEntry = builtins.filter (x: x.name == hostName) config.ghaf.networking.hosts.entries;
        addr = lib.head (builtins.map (x: x.ip) netvmEntry);
      in
      {
        enable = true;
        name = hostName;
        inherit addr;
        port = "9000";
        wifiManager = true;
        hwidService = true;
        tls.enable = config.ghaf.givc.enableTls;
        admin = config.ghaf.givc.adminConfig;
      };
  };
}
