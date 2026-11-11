# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ prev }:
if prev.stdenv.buildPlatform == prev.stdenv.hostPlatform then
  prev.chromium
else
  # Use the native target package so cross images can reuse the binary cache.
  (import prev.path {
    system = prev.stdenv.hostPlatform.system;
    inherit (prev) config;
  }).chromium
