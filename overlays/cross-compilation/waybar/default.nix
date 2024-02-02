# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Waybar cross-compilation fixes
#
{
  final,
  prev,
}:
prev.waybar.overrideAttrs (old: {
  nativeBuildInputs = [final.buildPackages.scdoc final.wrapGAppsHook final.catch2_3] ++ old.nativeBuildInputs;
  depsBuildBuild = [final.buildPackages.pkg-config final.buildPackages.wayland-scanner];
})
