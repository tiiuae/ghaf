# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Make panel applets respond to touch input.
# Applets bind only wl_pointer, so plain wl_touch events never reach them as
# clicks and tapping an applet does nothing on a touchscreen device.
# Ref: https://github.com/pop-os/cosmic-panel
{ prev }:
prev.cosmic-panel.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Emulate-pointer-clicks-for-touch-input.patch
  ];
})
