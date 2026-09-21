# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TII reference org configuration.A downstream project may supply its own org module.
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.org.tii;
in
{
  _file = ./tii.nix;

  options.ghaf.reference.org.tii.enable = lib.mkEnableOption "TII reference org configuration";

  config = lib.mkIf cfg.enable {
    ghaf.org = {
    };
  };
}
