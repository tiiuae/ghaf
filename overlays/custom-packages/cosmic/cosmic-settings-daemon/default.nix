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

  # Below is needed for cosmic DE and tools to query PipeWire on audio-vm
  # rather than any local PipeWire instance on the gui-vm
  # Ensure `config.ghaf.services.audio.client.enablePipewireControl` is enabled
  nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
    prev.buildPackages.makeWrapper
  ];

  postInstall = oldAttrs.postInstall or "" + ''
    wrapProgram "$out/bin/cosmic-settings-daemon" \
      --set PIPEWIRE_RUNTIME_DIR /tmp
  '';
}))
