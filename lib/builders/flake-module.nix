# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting builder functions
_: {
  # Export builder functions for downstream consumption
  flake.builders = {
    # Unified configuration builder
    mkGhafConfiguration = import ./mkGhafConfiguration.nix;

    # Unified installer builder
    mkGhafInstaller = import ./mkGhafInstaller.nix;
  };
}
