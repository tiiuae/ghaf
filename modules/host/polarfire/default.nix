# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.ghaf.host.polarfire;
in {
  imports = [
    self.nixosModules.ghaf.host
    self.nixosModules.ghaf.profiles.hostOnly
  ];

  options.ghaf.host.polarfire = {
    enable = lib.mkEnableOption "Enable Ghaf Polarfire host configuration";
  };

  config = lib.mkIf cfg.enable {
    #TODO are there any configs for here
    ghaf.host.enable = true;
    ghaf.profiles.hostOnly.enable = true;
  };
}
