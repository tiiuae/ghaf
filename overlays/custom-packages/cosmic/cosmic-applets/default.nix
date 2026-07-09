# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Add DBUS proxy socket for audio and Bluetooth applets
# Hidden buttons: airplane mode, media controls
# Ref: https://github.com/pop-os/cosmic-applets
{ prev }:
prev.cosmic-applets.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Hide-some-panel-buttons.patch
  ];
})
