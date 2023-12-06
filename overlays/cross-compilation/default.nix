# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
_: {
  nixpkgs.overlays = [
    (import ./edk2.nix)
    (import ./element-desktop.nix)
    (import ./firefox.nix)
    (import ./jbig2dec.nix)
    (import ./libjack.nix)
    (import ./sysbench.nix)
  ];
}
