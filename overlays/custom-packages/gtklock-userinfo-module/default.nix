# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Remove patch, once there new release for gtklock-userinfo-module
#
{ prev }:
prev.gtklock-userinfo-module.overrideAttrs {
  patches = [
    ./0001-update.patch
  ];
}
