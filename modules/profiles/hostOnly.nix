# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.hostOnly;
in
  with lib; {
    options.ghaf.profiles.hostOnly = {
      enable = mkEnableOption "Everything runs in the host, no virtualization";
    };

    config = mkIf cfg.enable {
      #cfg.isHostOnly = true;
      #TODO do we actually want to set anything else
    };
  }
