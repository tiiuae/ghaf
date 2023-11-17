# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
_: {
  nixpkgs.overlays = [
    (import ./sysbench.nix)
    (import ./element-desktop.nix)
    (import ./perl.nix)
    (import ./libjack.nix)
  ];
}
