# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Power Management Feature Module for VMs
#
# This module configures power management in guest VMs.
# Values are read from sharedSystemConfig passed via specialArgs.
#
{ config, lib, ... }:
let
  cfg = config.ghaf.services.power-manager;
in
{
  # Power management configuration for VMs
  # The enable flag comes from sharedSystemConfig
  config = lib.mkIf cfg.enable {
    # Power manager VM settings are configured in the VM builders
    # This module ensures the enable flag propagates correctly
  };
}
