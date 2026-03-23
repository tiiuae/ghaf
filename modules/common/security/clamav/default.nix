# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ClamAV antivirus module
#
# This module provides antivirus scanning capabilities for Ghaf, supporting both
# centralized host-based scanning and distributed guest-based configurations.
#
# Files:
#   options.nix  -> Option definitions
#   scripts.nix  -> Script helpers
#   services.nix -> ClamAV services
#   host.nix     -> Host-specific config
#   vm.nix       -> Guest-specific config
#
{
  _file = ./default.nix;

  imports = [
    ./options.nix
    ./services.nix
    ./host.nix
    ./vm.nix
  ];
}
