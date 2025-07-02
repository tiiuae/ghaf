# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# papirus-icon-theme cross-compilation fixes (removing qt dependency)
#
{ prev }:
prev.papirus-icon-theme.overrideAttrs (old: {
  propagatedBuildInputs = prev.lib.lists.remove prev.kdePackages.breeze-icons old.propagatedBuildInputs;
})
