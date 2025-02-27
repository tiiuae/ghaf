# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  qemu_kvm = prev.qemu_kvm.overrideAttrs (
    # Patches from https://github.com/jpruiz84/qemu/tree/bpmp_for_v9.2
    _final: prev: { patches = prev.patches ++ [ 
      ./patches/0001-nvidia-bpmp-guest-driver-initial-commit.patch
    ];}
  );
})
