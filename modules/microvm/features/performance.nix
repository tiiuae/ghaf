# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Performance Monitoring Feature Module for VMs
#
# This module configures performance monitoring in guest VMs.
# Values are read from sharedSystemConfig passed via specialArgs.
#
{ config, lib, ... }:
let
  cfg = config.ghaf.services.performance;
in
{
  # Performance monitoring configuration for VMs
  # The enable flag comes from sharedSystemConfig
  config = lib.mkIf cfg.enable {
    # Performance settings are configured in the VM builders
    # This module ensures the enable flag propagates correctly
  };
}
