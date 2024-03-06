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
  replace = haystack: needle: replacement:
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
              depsBuildBuild = replace finalAttrs.depsBuildBuild (final.libpng.override {apngSupport = false;}) final.libpng;
            }
            // fun finalAttrs);
      };
  })
