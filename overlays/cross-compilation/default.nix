# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
(final: prev: {
  chromium = import ./chromium {inherit prev final;};
  edk2 = import ./edk2 {inherit final prev;};
  element-desktop = import ./element-desktop {inherit prev;};
  jbig2dec = import ./jbig2dec {inherit prev;};
  pipewire = import ./pipewire {inherit prev;};

  # libck is dependency of sysbench
  libck = import ./libck {inherit prev;};
  sysbench = import ./sysbench {inherit final prev;};
})
