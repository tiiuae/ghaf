# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  element-desktop = prev.element-desktop.overrideAttrs (_final: _prev: {
    patches = [./element-main.patch];
  });
})
