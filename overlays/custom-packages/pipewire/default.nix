# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.pipewire.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-zeroconf-discover-allow-nodes-with-same-names.patch
  ];
})
