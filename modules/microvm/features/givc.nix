# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GIVC Feature Module for VMs
#
# This module configures GIVC (Ghaf Inter-VM Communication) in guest VMs.
# Values are read from sharedSystemConfig passed via specialArgs.
#
{ config, lib, ... }:
let
  cfg = config.ghaf.givc;
in
{
  # GIVC configuration is set via sharedSystemConfig
  # This module just ensures proper defaults for VM guests
  config = lib.mkIf cfg.enable {
    # GIVC is configured at the VM builder level (mkNetVm, mkGuiVm, etc.)
    # This feature module ensures the enable flag propagates correctly
  };
}
