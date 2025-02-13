# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.services.wireguard-gui;
  options = {
    ghaf.services.wireguard-gui = {
      enable = lib.mkEnableOption "WireGuard VPN configuration tool for app-vms";
      vms = lib.mkOption {
        type = with lib.types; listOf str;
        description = "List of app-vms names as in microvm configuration.";
        default = [ ];
      };
    };
  };
in
{
  inherit options;
  config =
    lib.mkIf
      (
        cfg.enable
        && lib.attrsets.hasAttrByPath [
          "microvm"
          "vms"
        ] config
      )
      {
        ghaf = {
          virtualization.microvm = {
            appvm.vms =
              let
                vmConfigs = map (vm: {
                  ${vm}.extraModules = [
                    (import ./wireguard-gui-vm-conf.nix {
                      inherit vm;
                      hostConfig = config;
                    })
                  ];
                }) cfg.vms;
              in
              lib.foldr lib.recursiveUpdate { } vmConfigs;
            guivm.extraModules = [
              {
                inherit options;
                config = {
                  ghaf.services.wireguard-gui.enable = cfg.enable;
                  ghaf.services.wireguard-gui.vms = cfg.vms;
                };
              }
            ];
          };
        };
      };
}
