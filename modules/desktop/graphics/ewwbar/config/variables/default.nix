# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  callPackage,
  writeText,
  setxkbmap,
  ewwScripts,
  gawk,
  ...
}:
let
  ghaf-workspace = callPackage ../../../../../../packages/ghaf-workspace { };
in
writeText "variables.yuck" ''
  (defpoll keyboard_layout :interval "5s" "${setxkbmap}/bin/setxkbmap -query | ${gawk}/bin/awk '/layout/{print $2}' | tr a-z A-Z")
  (defpoll battery :interval "5s" :initial "{}" "${ewwScripts.eww-bat}/bin/eww-bat get")
  (deflisten brightness :initial "{}" "${ewwScripts.eww-brightness}/bin/eww-brightness listen")
  (deflisten audio_output :initial "{}" "${ewwScripts.eww-audio}/bin/eww-audio listen_output")
  (deflisten audio_input :initial "{}" "${ewwScripts.eww-audio}/bin/eww-audio listen_input")
  (defpoll audio_outputs :interval "1s" "${ewwScripts.eww-audio}/bin/eww-audio get_outputs")
  (defpoll audio_inputs :interval "1s" "${ewwScripts.eww-audio}/bin/eww-audio get_inputs")
  (defpoll audio_streams :interval "60s" "echo []")
  (deflisten workspace :initial "1" "${ghaf-workspace}/bin/ghaf-workspace subscribe")

  (defvar volume-popup-visible "false")
  (defvar brightness-popup-visible "false")
  (defvar workspace-popup-visible "false")
  (defvar workspaces-visible "false")
  (defvar volume-mixer-visible "false")
  (defvar audio_output_selector_visible "false")
  (defvar audio_input_selector_visible "false")
''
