# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.profiles.mvp-hardened;
  inherit (lib) mkEnableOption mkIf;
in
{
  imports = [ ../hardened ];

  options.ghaf.reference.profiles.mvp-hardened = {
    enable = mkEnableOption "Enable the mvp hardened configuration";
  };

  # Enable secure boot in the host configuration
  config = mkIf cfg.enable { ghaf.reference.hardened.host-hardened.enable = true; };
}
