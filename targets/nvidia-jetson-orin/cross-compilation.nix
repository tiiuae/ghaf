# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Cross-compilation module
#
{
  nixpkgs = {
    #TODO: move this to the targets dir and call this from the cross-targets
    #section under the -from-x86_64 section
    buildPlatform.system = "x86_64-linux";
    overlays = [ (import ../../overlays/cross-compilation) ];
  };
}
