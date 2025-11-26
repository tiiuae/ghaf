# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ prev }:
prev.osquery.overrideAttrs (old: {
  pname = "osquery-with-hostname";
  patches = (old.patches or [ ]) ++ [
    ./hostname-file.patch
  ];
})
