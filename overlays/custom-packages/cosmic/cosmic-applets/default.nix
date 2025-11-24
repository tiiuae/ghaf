# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Add DBUS proxy socket for audio and Bluetooth applets
# audio-applet: patch to hide sound settings button
# bluetooth-applet: patch to hide bluetooth settings button
# network-applet: patch to hide airplane mode toggle
# Ref: https://github.com/pop-os/cosmic-applets
{ prev }:
prev.cosmic-applets.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    # audio and bluetooth patches should be removed when dbus-proxy allows
    ./0001-audio-applet-hide-sound-settings-button.patch
    ./0001-bluetooth-applet-hide-bluetooth-settings-button.patch
    ./0001-network-applet-hide-airplane-mode-toggle.patch
  ];
  postInstall = oldAttrs.postInstall or "" + ''
    sed -i 's|^Exec=.*|Exec=env DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock cosmic-applet-audio|' $out/share/applications/com.system76.CosmicAppletAudio.desktop
    sed -i 's|^Exec=.*|Exec=env DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock cosmic-applet-bluetooth|' $out/share/applications/com.system76.CosmicAppletBluetooth.desktop
  '';
})
