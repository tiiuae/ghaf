# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
(prev.cosmic-osd.overrideAttrs (oldAttrs: {
  # `paplay` rather than `pw-play`, which does not work in gui-vm
  # Technically, no need to replace with paplay, as we disable audio playback
  # entirely below, but just in case any code paths remain that try to play audio
  postPatch = oldAttrs.postPatch or "" + ''
    substituteInPlace src/components/app.rs \
      --replace-fail "pw-play" "paplay" \
      --replace '.arg("--media-role")' "" \
      --replace '.arg("Notification")' ""

    # Disable audio playback entirely, to prevent excessive CPU usage
    # Volume change pops will be handled by ghaf-volume script instead
    substituteInPlace src/components/app.rs \
      --replace-fail "pipewire::play_audio_volume_change();" ""
  '';
}))
