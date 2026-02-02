# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Security Audit Feature Module for VMs
#
# This module configures security auditing in guest VMs.
# Values are read from sharedSystemConfig passed via specialArgs.
#
{ config, lib, ... }:
let
  cfg = config.ghaf.security.audit;
in
{
  # Audit configuration for VMs
  # The enable flag comes from sharedSystemConfig
  config = lib.mkIf cfg.enable {
    # Security audit settings are applied when enabled
    # Specific audit rules are defined in the security module
  };
}
