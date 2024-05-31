# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
(final: prev: {
  chromium = import ./chromium {inherit prev final;};
  jbig2dec = import ./jbig2dec {inherit prev;};
  pipewire = import ./pipewire {inherit prev;};
})
