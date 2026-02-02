# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Logging Feature Module for VMs
#
# This module configures logging in guest VMs.
# Values are read from sharedSystemConfig passed via specialArgs.
#
{ config, lib, ... }:
let
  cfg = config.ghaf.logging;
in
{
  # Logging client configuration for VMs
  # The enable flag and listener/server settings come from sharedSystemConfig
  config = lib.mkIf cfg.enable {
    ghaf.logging.client.enable = lib.mkDefault true;
  };
}
