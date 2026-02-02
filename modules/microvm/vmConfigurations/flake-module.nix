# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Configurations Flake Module
#
# Note: VM builders and mkSharedSystemConfig are now exported via flake.lib
# in the main flake.nix. This file only exports the vmBase NixOS module.
#
_: {
  # Export base VM configuration as a NixOS module
  # Usage: self.nixosModules.vmBase
  flake.nixosModules.vmBase = import ./base.nix;
}
