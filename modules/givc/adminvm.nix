# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.adminvm;
  inherit (lib) mkEnableOption mkIf mkDefault;
  inherit (config.ghaf.givc.adminConfig) name;
  systemHosts = lib.lists.subtractLists (config.ghaf.common.appHosts ++ [ name ]) (
    builtins.attrNames config.ghaf.networking.hosts
  );
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
      inherit name;
      inherit (config.ghaf.givc.adminConfig) addresses;
      services = map (host: "givc-${host}.service") systemHosts;
      tls.enable = config.ghaf.givc.enableTls;
      opa = {
        enable = mkDefault true;
        policyPath = mkDefault ./../../policies/default-policy;
      };
    };
  };
}
