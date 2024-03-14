# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay hides the desktop entry for htop
#
{prev}:
prev.htop.overrideAttrs {
  postInstall = ''
    echo "Hidden=true" >> $out/share/applications/htop.desktop
  '';
}
