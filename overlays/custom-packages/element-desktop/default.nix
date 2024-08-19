# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes element-desktop
#
{ prev }:
prev.element-desktop.overrideAttrs (_prevAttrs: {
  patches = [ ./element-main.patch ];
})
