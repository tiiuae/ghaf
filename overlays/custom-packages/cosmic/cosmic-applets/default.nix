# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Add DBUS proxy socket for audio and Bluetooth applets
# audio-applet: add button to refresh audio devices
# network-applet: patch to hide airplane mode toggle
# Ref: https://github.com/pop-os/cosmic-applets
{ prev }:
prev.cosmic-applets.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-audio-applet-add-refresh-audio-devices-button.patch
    ./0001-network-applet-hide-airplane-mode-toggle.patch
  ];
})
