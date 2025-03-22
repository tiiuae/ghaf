# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui-config;
  inherit (config.ghaf.reference) services;
  inherit (lib)
    mkOption
    mkIf
    types
    ;
in
{
  options.ghaf.reference.services.wireguard-gui-config = {
    vms = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of VM names where Wireguard GUI should be enabled.";
      example = [
        "gui-vm"
        "net-vm"
      ];
    };
  };

  config = mkIf (cfg.vms != [ ]) {

    environment.etc."ctrl-panel/wireguard-gui-vms.txt" =
      let
        vmstxt = lib.concatStringsSep "\n" cfg.vms;
      in
      {
        text = ''
          ${vmstxt}
        '';
      };
  };
}
