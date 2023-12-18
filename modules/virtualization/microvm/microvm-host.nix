# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.ghaf.virtualization.microvm-host;
  inherit (inputs) microvm;
in
  with lib; {
    imports = [
      microvm.nixosModules.host
    ];

    options.ghaf.virtualization.microvm-host = {
      enable = mkEnableOption "MicroVM Host";
    };

    config = mkIf cfg.enable {
      microvm.host.enable = true;
    };
  }
