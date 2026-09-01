# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# yad 15.0 turns on four optional backends that 14.1 did not have, and nixpkgs
# enables all of them. They cost 536 MB of closure on every ghaf image:
#
#   --enable-html          webkitgtk_4_1   (the bulk of it, and built from source)
#   --enable-sourceview    gtksourceview
#   --enable-spell         gspell
#   --enable-appindicator  libappindicator
#
# Measured on x86_64: 847.1 MB -> 310.8 MB.
#
# xdgflatpakurl, the flatpak VM's "no App Store browser" dialog and windows-launcher
# use yad.
{ prev }:
(prev.yad.override {
  gtksourceview = null;
  gspell = null;
  libappindicator = null;
  webkitgtk_4_1 = null;
}).overrideAttrs
  (old: {
    configureFlags = builtins.filter (
      flag:
      !(builtins.elem flag [
        "--enable-appindicator"
        "--enable-html"
        "--enable-sourceview"
        "--enable-spell"
      ])
    ) old.configureFlags;
  })
