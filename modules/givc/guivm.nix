# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.guivm;
  inherit (lib) mkEnableOption mkIf;
  hostName = "gui-vm";
in
{
  options.ghaf.givc.guivm = {
    enable = mkEnableOption "Enable guivm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure guivm service
    givc.sysvm =
      let
        guivmEntry = builtins.filter (x: x.name == hostName) config.ghaf.networking.hosts.entries;
        addr = lib.head (builtins.map (x: x.ip) guivmEntry);
      in
      {
        enable = true;
        name = hostName;
        inherit addr;
        port = "9000";
        tls.enable = config.ghaf.givc.enableTls;
        admin = config.ghaf.givc.adminConfig;
      };
  };
}
