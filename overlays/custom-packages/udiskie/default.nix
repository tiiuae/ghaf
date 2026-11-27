# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
(prev.udiskie.overrideAttrs (oldAttrs: {
  postPatch = (oldAttrs.postPatch or "") + ''
    # Override default tray icon
    substituteInPlace udiskie/tray.py \
      --replace-fail "drive-removable-media-usb-panel" "drive-removable-media"

    # Backport upstream fix: https://github.com/coldfix/udiskie/pull/362
    substituteInPlace udiskie/keyutils.py \
      --replace-fail "return buffer.value" "return buffer.raw[:ret]"
  '';
}))
