# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.virtualization.docker.daemon;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.ghaf.virtualization.docker.daemon = {
    enable = mkEnableOption "Docker Daemon";
  };

  config = mkIf cfg.enable {
    virtualisation.docker.enable = true;
    virtualisation.docker.rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
