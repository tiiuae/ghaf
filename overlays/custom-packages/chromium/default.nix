# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ prev }:
if prev.stdenv.buildPlatform == prev.stdenv.hostPlatform then
  prev.chromium
else
  # Keep Ghaf overlays in the native target package, just as in native images.
  # A cache miss requires a target-system builder;
  # this package is not cross-compiled by the x86 image builder.
  (import prev.path {
    system = prev.stdenv.hostPlatform.system;
    inherit (prev) config overlays;
  }).chromium
