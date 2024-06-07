# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.programs.zathura;
in {
  options.ghaf.programs.zathura = {
    enable = lib.mkEnableOption "Enable Zathura program settings";
  };
  config = lib.mkIf cfg.enable {
    # Use regular clipboard instead of primary clipboard.
    environment.etc."zathurarc".text = ''
      set selection-clipboard clipboard
    '';
  };
}
