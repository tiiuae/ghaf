# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Cross-compilation module
#
{
  nixpkgs = {
    buildPlatform.system = "x86_64-linux";
    overlays = [ (import ../../overlays/cross-compilation) ];
  };
}
