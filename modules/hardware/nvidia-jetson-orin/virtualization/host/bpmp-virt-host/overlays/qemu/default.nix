# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  qemu = prev.qemu.overrideAttrs (_final: prev: {
    patches =
      prev.patches
      ++ [
        ./patches/0001-qemu-v8.0.5_bpmp-virt.patch
      ];
  });
})
