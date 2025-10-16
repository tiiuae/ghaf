# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui-config;
  inherit (lib)
    mkOption
    mkIf
    types
    mkEnableOption
    ;
in
{
  options.ghaf.reference.services.wireguard-gui-config = {
    vms = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of VM names where Wireguard GUI should be enabled.";
      example = [
        "business-vm"
        "chrome-vm"
      ];
    };
    enable = mkEnableOption "Wireguard guivm configuration";
  };

  config = mkIf cfg.enable {

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
