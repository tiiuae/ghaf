# Copyright 2023-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Chromium & Electron cross-compilation fixes
#
{
  final,
  prev,
}: let
  inherit (builtins) map;
  inherit (final.lib) pipe;
  opusWithCustomModes = final.pkgsBuildBuild.libopus.override {
    withCustomModes = true;
  };
  opusWithCustomModes' = final.pkgsBuildTarget.libopus.override {
    withCustomModes = true;
  };
  replace = needle: replacement: haystack:
    map (each:
      if each == needle
      then replacement
      else each)
    haystack;
in
  prev.chromium.overrideAttrs (oa: {
    passthru =
      oa.passthru
      // {
        mkDerivation = fun:
          oa.passthru.mkDerivation (finalAttrs:
            {
              depsBuildBuild = pipe finalAttrs.depsBuildBuild [
                (replace (final.libpng.override {apngSupport = false;}) (final.pkgsBuildBuild.libpng.override {apngSupport = false;}))
                (replace final.zlib final.pkgsBuildBuild.zlib)
                (replace opusWithCustomModes opusWithCustomModes')
              ];
              buildInputs = replace opusWithCustomModes' opusWithCustomModes finalAttrs.buildInputs;
              env = finalAttrs.env // {NIX_DEBUG = "1";};
            }
            // fun finalAttrs);
      };
  })
