# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Show the Ghaf VM an app runs in as its app source badge
# Ref: https://github.com/pop-os/cosmic-app-library
{ prev }:
prev.cosmic-app-library.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    ./0001-Show-Ghaf-VM-as-app-source.patch
  ];
})
