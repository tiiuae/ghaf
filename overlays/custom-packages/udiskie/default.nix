# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
(prev.udiskie.overrideAttrs (oldAttrs: {
  # Override default tray icon
  postPatch = (oldAttrs.postPatch or "") + ''
    substituteInPlace udiskie/tray.py \
      --replace-fail "drive-removable-media-usb-panel" "drive-removable-media-usb-pendrive-symbolic"
  '';
}))
