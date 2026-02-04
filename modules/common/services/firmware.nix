# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.firmware;
  inherit (lib) mkIf mkEnableOption;
  isX86_64 = pkgs.stdenv.hostPlatform.isx86_64;
in
{
  _file = ./firmware.nix;

  options.ghaf.services.firmware = {
    enable = mkEnableOption "PLaceholder for firmware handling";
  };
  config = mkIf (cfg.enable && isX86_64) {
    hardware = {
      enableAllFirmware = true;
    };
  };
}
