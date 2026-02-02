# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting builder functions
#
# VM builders and mkSharedSystemConfig are exported via:
# - self.lib.vmBuilders (mkNetVm, mkGuiVm, mkAudioVm, mkAdminVm, mkIdsVm, mkAppVm)
# - self.lib.mkSharedSystemConfig
#
# These exports are defined in modules/microvm/vmConfigurations/flake-module.nix
#
_: {
  # Export target builder functions for downstream consumption
  flake.builders = {
    # Target builders
    mkLaptopConfiguration = import ./mkLaptopConfiguration.nix;
    mkLaptopInstaller = import ./mkLaptopInstaller.nix;
  };
}
