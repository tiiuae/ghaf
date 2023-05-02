# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  nixpkgs.overlays = [
    (final: prev: {
      gala-app = pkgs.callPackage ./gala {};
      windows-launcher = pkgs.callPackage ./windows-launcher {};
    })
  ];
}
