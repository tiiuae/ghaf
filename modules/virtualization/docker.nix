# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  modulesPath,
  ...
}: let
  cfg = config.ghaf.virtualization.docker.daemon;
in
  with lib; {
    options.ghaf.virtualization.docker.daemon = {
      enable = mkEnableOption "Docker Daemon";
    };

    config = mkIf cfg.enable {
      imports = [
        (modulesPath + "/virtualisation/docker.nix")
      ];

      virtualisation.docker.enable = true;
      virtualisation.docker.rootless = {
        enable = true;
        setSocketVariable = true;
      };
    };
  }
