# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.host.powercontrol;
in
{
  options.ghaf.host.powercontrol.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable host power control";
  };

  config = lib.mkIf cfg.enable { };
}
