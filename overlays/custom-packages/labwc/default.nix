# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes labwc - see comments for details
#
{
  final,
  prev,
}:
prev.labwc.overrideAttrs (prevAttrs: {
  patches = [./labwc-colored-borders.patch];
  buildInputs = with final;
    [
      foot
      swaybg
      kanshi
      waybar
      mako
      swayidle
    ]
    ++ prevAttrs.buildInputs;
  preInstallPhases = ["preInstallPhase"];
  preInstallPhase = ''
    substituteInPlace ../docs/autostart \
     --replace "swaybg -c '#113344'" '${final.swaybg}/bin/swaybg -m fill -i ${../../../assets/wallpaper.png}' \
     --replace kanshi ${final.kanshi}/bin/kanshi \
     --replace waybar "${final.waybar}/bin/waybar -s /etc/waybar/style.css -c /etc/waybar/config" \
     --replace mako ${final.mako}/bin/mako \
     --replace swayidle ${final.swayidle}/bin/swayidle

    substituteInPlace ../docs/menu.xml \
     --replace alacritty ${final.foot}/bin/foot

    substituteInPlace ../docs/environment \
     --replace 'XKB_DEFAULT_LAYOUT=se,de' ""
    substituteInPlace ../docs/environment \
     --replace 'XKB_DEFAULT_LAYOUT=se' ""

    #frame coloring example
    substituteInPlace ../docs/rc.xml \
     --replace '</labwc_config>' \
     '<windowRules><windowRule identifier="Foot" borderColor="#00ffff" serverDecoration="yes" skipTaskbar="no"  /></windowRules></labwc_config>'

    chmod +x ../docs/autostart
  '';
})
