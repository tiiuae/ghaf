# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# gcr_4 cross-compilation fixes
#
{
  final,
  prev,
}:
prev.gcr_4.overrideAttrs (old: {
  nativeBuildInputs = [final.gnupg] ++ old.nativeBuildInputs;
})
