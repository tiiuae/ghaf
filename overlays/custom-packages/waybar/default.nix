# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes waybar
#
{ prev }:
(prev.waybar.override {
  hyprlandSupport = false;
  swaySupport = false;
  jackSupport = false;
  cavaSupport = false;
  pulseSupport = false;
})
