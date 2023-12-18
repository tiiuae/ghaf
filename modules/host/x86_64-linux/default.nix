# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.ghaf.host.x86_64-linux;
in {
  imports = [
    self.nixosModules.ghaf.host

    #TODO remove this when the overlays are merget to pkgs
    ../../../overlays/custom-packages

    ./kernel.nix
  ];

  options.ghaf.host.x86_64-linux = {
    enable = lib.mkEnableOption "Enable Ghaf x86_64-linux host configuration";
  };

  config = lib.mkIf cfg.enable {
    ghaf.host.enable = true;
  };
}
