# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Added by the theming module
# Removes desktop entries for QT helper apps
{ prev }:
prev.qt6Packages.overrideScope (
  _final: pkgSet: {
    qt6ct = pkgSet.qt6ct.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        rm -rf "$out/share/applications"
      '';
    });
    qtstyleplugin-kvantum = pkgSet.qtstyleplugin-kvantum.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        rm -rf "$out/share/applications"
      '';
    });
  }
)
