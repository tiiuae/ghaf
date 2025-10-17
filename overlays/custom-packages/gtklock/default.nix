# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Remove patch, once the fix is available in gtklock
#
# https://github.com/jovanlanik/gtklock/pull/119
#
{ prev }:
prev.gtklock.overrideAttrs (oldAttrs: {
  patches = [
    ./0001-Multiple-errors-on-wrong-password.patch
  ];

  postInstall = ''
    mkdir -p $out/share/layout
    cp ${oldAttrs.src}/res/gtklock.ui $out/share/layout/gtklock.ui.xml
  '';
})
