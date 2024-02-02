# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# wlroots cross-compilation fixes
#
{
  final,
  prev,
}:
prev.wlroots.overrideAttrs (old: {
  nativeBuildInputs = old.nativeBuildInputs ++ [final.hwdata];
})
