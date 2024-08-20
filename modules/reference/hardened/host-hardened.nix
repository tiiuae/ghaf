# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.hardened.host-hardened;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.ghaf.reference.hardened.host-hardened = {
    enable = mkEnableOption "Host hardened configuration";
  };

  # Enable secure boot in the host configuration
  config = mkIf cfg.enable { ghaf.host.secureboot.enable = true; };
}
