# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes crosvm
#
{ prev }:
prev.crosvm.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [ ./0001-devices-input-Return-empty-string-if-EVIOCGUNIQ-retu.patch ];
})
