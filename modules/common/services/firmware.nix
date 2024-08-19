# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.services.firmware;
  inherit (lib) mkIf mkEnableOption;
in
{
  options.ghaf.services.firmware = {
    enable = mkEnableOption "PLaceholder for firmware handling";
  };
  config = mkIf cfg.enable {
    hardware = {
      enableRedistributableFirmware = true;
      enableAllFirmware = true;
    };
  };
}
