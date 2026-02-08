# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.adminvm;
  inherit (lib) mkEnableOption mkIf;
  inherit (config.ghaf.givc.adminConfig) name;
  systemHosts = lib.lists.subtractLists (config.ghaf.common.appHosts ++ [ name ]) (
    builtins.attrNames config.ghaf.networking.hosts
  );
in
{
  _file = ./adminvm.nix;

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
    };
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${name}"
    ];
  };
}
