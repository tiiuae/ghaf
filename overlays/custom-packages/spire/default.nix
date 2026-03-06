# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ prev }:
prev.spire.overrideAttrs (_oldAttrs: {
  patches = [
    ./0001-remove-cloud-components-to-reduce-memory-footprint.patch
  ];
})
