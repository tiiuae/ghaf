# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay hides the desktop entry for network settings
#
{prev}:
prev.networkmanagerapplet.overrideAttrs {
  postInstall = ''
    echo "Hidden=true" >> $out/share/applications/nm-connection-editor.desktop
  '';
}
