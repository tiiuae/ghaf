# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.spire.overrideAttrs (oldAttrs: {
  pname = "spire4ghaf";
  patches = (oldAttrs.patches or [ ]) ++ [
    ./0001-spire-with-basic-plugins.patch
  ];
})
