# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, pkgs, ... }:
let
  cfg = config.ghaf.givc.adminvm;
  inherit (lib) mkEnableOption mkIf;
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
      policyAdmin = {
        enable = true;
        url = "https://github.com/gngram/policy-store.git";
        rev = "77f54de54ef8640abb079bf60e5468d9694d850d";
        sha256 = "sha256-uStBhfEPwKXClqEeILzECqLrpCG/M/OG+RejZ5U+yvQ=";
        opa.enable = true;
        monitor.enable = true;
        monitor.ref = "deploy";
      };
    };
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${name}"
    ];
  };
}
