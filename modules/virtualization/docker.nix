# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  modulesPath,
  ...
}: let
  cfg = config.ghaf.virtualization.docker.daemon;
in
  with lib; {
    options.ghaf.virtualization.docker.daemon = {
      enable = mkEnableOption "Docker Daemon";
    };

    imports = [(modulesPath + "/virtualisation/docker.nix")];
    config = mkIf cfg.enable {
      virtualisation.docker.enable = true;
      virtualisation.docker.rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  }
