# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Features Module Bundle
#
# This module bundles all VM feature modules for easy import.
# Feature modules read their configuration from sharedSystemConfig,
# which is passed via specialArgs from the target builders.
#
# Usage:
#   # In VM configuration:
#   imports = [ self.nixosModules.vm-features ];
#
#   # Features are automatically configured based on sharedSystemConfig values
#
{
  imports = [
    ./givc.nix
    ./logging.nix
    ./audit.nix
    ./power.nix
    ./performance.nix
    ./users.nix
    ./common.nix
  ];
}
