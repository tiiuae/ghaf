# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# A template for creating modules for Ghaf
# for more information on writing templates please refer to the manual
#
# https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules
#
{ config, lib, ... }:
let
  # inherit (builtins) A B C;
  # inherit (lib) D E F;
  # inherit (lib.ghaf) G H I;
  cfg = config.ghaf.X.Y;
in
{
  imports = [ ];

  options.ghaf.X.Y = {
    enable = lib.mkEnableOption "Option";
  };

  config = lib.mkIf cfg.enable { };
}
