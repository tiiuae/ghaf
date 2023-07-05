# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.services.avahi;
in
  with lib; {
    options.ghaf.services.avahi = {
      enable = mkEnableOption "Service avahi";
    };

    config = mkIf cfg.enable {
      services.avahi = {
        enable = true;
        nssmdns = true;
        publish.addresses = true;
        publish.domain = true;
        publish.enable = true;
        publish.userServices = true;
        publish.workstation = true;
      };
    };
  }
