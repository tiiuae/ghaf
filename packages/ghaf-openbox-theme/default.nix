# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ runCommand, ... }:
runCommand "ghaf-openbox-theme" { } ''
  mkdir -p $out/share/themes/Ghaf/openbox-3
  cp ${../../assets/icons/svg/close.svg} $out/share/themes/Ghaf/openbox-3/close.svg
  ln -s $out/share/themes/Ghaf/openbox-3/close{,-active}.svg
  ln -s $out/share/themes/Ghaf/openbox-3/close{,-inactive}.svg
  cp ${../../assets/icons/svg/max.svg}  $out/share/themes/Ghaf/openbox-3/max.svg
  ln -s $out/share/themes/Ghaf/openbox-3/max{,-active}.svg
  ln -s $out/share/themes/Ghaf/openbox-3/max{,-inactive}.svg
  ln -s $out/share/themes/Ghaf/openbox-3/max{,_toggled-active}.svg
  ln -s $out/share/themes/Ghaf/openbox-3/max{,_toggled-inactive}.svg
  cp ${../../assets/icons/svg/iconify.svg}  $out/share/themes/Ghaf/openbox-3/iconify.svg
  ln -s $out/share/themes/Ghaf/openbox-3/iconify{,-active}.svg
  ln -s $out/share/themes/Ghaf/openbox-3/iconify{,-inactive}.svg
  cp ${../../assets/icons/svg/icon_arrow.svg}  $out/share/themes/Ghaf/openbox-3/menu.svg
  ln -s $out/share/themes/Ghaf/openbox-3/menu{,-active}.svg
  ln -s $out/share/themes/Ghaf/openbox-3/menu{,-inactive}.svg

  cp ${./themerc}  $out/share/themes/Ghaf/openbox-3/themerc
''
