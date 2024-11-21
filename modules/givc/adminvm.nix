# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.adminvm;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.ghaf.givc.adminvm = {
    enable = mkEnableOption "Enable adminvm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure admin service
    givc.admin = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit (config.ghaf.givc.adminConfig) name;
      inherit (config.ghaf.givc.adminConfig) addr;
      inherit (config.ghaf.givc.adminConfig) port;
      inherit (config.ghaf.givc.adminConfig) protocol;
      services = [
        "givc-ghaf-host-debug.service"
        "givc-net-vm.service"
        "givc-gui-vm.service"
        "givc-audio-vm.service"
      ];
      tls.enable = config.ghaf.givc.enableTls;
    };
  };
}
