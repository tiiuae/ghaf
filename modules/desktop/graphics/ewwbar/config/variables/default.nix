# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  writeText,
  setxkbmap,
  ewwScripts,
  gawk,
  ghaf-workspace,
  ...
}:
writeText "variables.yuck" ''
  (defpoll keyboard_layout :interval "5s" "${setxkbmap}/bin/setxkbmap -query | ${gawk}/bin/awk '/layout/{print $2}' | tr a-z A-Z")
  (defpoll battery  :interval "5s" :initial "{}" "${ewwScripts.eww-bat}/bin/eww-bat get")
  (deflisten brightness :initial "{}" "${ewwScripts.eww-brightness}/bin/eww-brightness listen")
  (deflisten volume :initial "{}" "${ewwScripts.eww-volume}/bin/eww-volume listen")
  (deflisten workspace :initial "1" "${ghaf-workspace}/bin/ghaf-workspace subscribe")

  (defvar calendar_day "date '+%d'")
  (defvar calendar_month "date '+%-m'")
  (defvar calendar_year "date '+%Y'")

  (defvar volume-popup-visible "false")
  (defvar brightness-popup-visible "false")
  (defvar workspace-popup-visible "false")
  (defvar workspaces-visible "false")
  (defvar volume-mixer-visible "false")
  (defvar mixer-sliders "")
''
