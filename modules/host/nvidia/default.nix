# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.ghaf.host.nvidia;
in {
  imports = [
    self.nixosModules.ghaf.host

    #TODO remove this when the overlays are merget to pkgs
    ../../../overlays/custom-packages
  ];

  options.ghaf.host.nvidia = {
    enable = lib.mkEnableOption "Enable Ghaf Nvidia host configuration";
  };

  config = lib.mkIf cfg.enable {
    ghaf.host.enable = true;
  };
}
