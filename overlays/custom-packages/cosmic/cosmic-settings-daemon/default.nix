# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
(prev.cosmic-settings-daemon.overrideAttrs (oldAttrs: {
  # `paplay` rather than `pw-play`, which does not work in gui-vm
  postPatch = oldAttrs.postPatch or "" + ''
    substituteInPlace src/pipewire.rs \
      --replace-fail "pw-play" "paplay" \
      --replace '.arg("--media-role")' "" \
      --replace '.arg("Notification")' ""
  '';
}))
