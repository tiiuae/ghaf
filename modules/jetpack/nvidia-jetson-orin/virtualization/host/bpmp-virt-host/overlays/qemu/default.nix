# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  qemu_kvm = prev.qemu_kvm.overrideAttrs (
    _final: prev: { patches = prev.patches ++ [ ./patches/0001-qemu-v8.1.3_bpmp-virt.patch ]; }
  );
})
