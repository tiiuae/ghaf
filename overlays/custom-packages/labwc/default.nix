# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes labwc - see comments for details
#
(final: prev: {
  labwc = prev.labwc.overrideAttrs (prevAttrs: {
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
       --replace swaybg ${final.swaybg}/bin/swaybg \
       --replace kanshi ${final.kanshi}/bin/kanshi \
       --replace waybar "${final.waybar}/bin/waybar -s /etc/waybar/style.css -c /etc/waybar/config" \
       --replace mako ${final.mako}/bin/mako \
       --replace swayidle ${final.swayidle}/bin/swayidle

       substituteInPlace ../docs/menu.xml \
       --replace alacritty ${final.foot}/bin/foot

       chmod +x ../docs/autostart
    '';
  });
})
