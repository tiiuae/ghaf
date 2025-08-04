# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is based on following PR - https://github.com/NixOS/nixpkgs/pull/429900
{ prev, final }:
let
  isCross = prev.stdenv.hostPlatform != prev.stdenv.buildPlatform;
  inherit (prev) lib;
in
prev.v4l-utils.overrideAttrs (oldAttrs: {
  preConfigure =
    (oldAttrs.preConfigure or "")
    + lib.optionalString isCross ''
      export PATH=${final.buildPackages.qt6Packages.qtbase}/libexec:$PATH
    '';
  mesonFlags =
    (oldAttrs.mesonFlags or [ ])
    ++ lib.optionals isCross [
      "-Dbpf=disabled"
    ];
})
