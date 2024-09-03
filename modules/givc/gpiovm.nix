# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  ...
}:
let
  cfg = config.ghaf.givc.gpiovm;
  inherit (lib) mkEnableOption mkIf;
  hostName = "gpio-vm";
in
{
  options.ghaf.givc.gpiovm = {
    enable = mkEnableOption "Enable gpiovm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure gpiovm service
    givc.sysvm =
      let
        gpiovmEntry = builtins.filter (x: x.name == hostName) config.ghaf.networking.hosts.entries;
        addr = lib.head (builtins.map (x: x.ip) gpiovmEntry);
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
