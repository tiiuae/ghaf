# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  microvm,
  netvm,
}: {
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.virtualization.microvm-host;
in
  with lib; {
    options.ghaf.virtualization.microvm-host = {
      enable = mkEnableOption "MicroVM Host";
    };

    imports = [
      microvm.nixosModules.host
    ];

    config = mkIf cfg.enable {
      microvm.host.enable = true;

      microvm.vms."${netvm}" = {
        flake = self;
        autostart = true;
      };
    };
  }
