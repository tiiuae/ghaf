# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.programs.zathura;
in
{
  _file = ./zathura.nix;

  options.ghaf.reference.programs.zathura = {
    enable = lib.mkEnableOption "Enable Zathura program settings";
  };
  config = lib.mkIf cfg.enable {
    # Use regular clipboard instead of primary clipboard.
    environment.etc."zathurarc".text = ''
      set selection-clipboard clipboard
    '';
  };
}
