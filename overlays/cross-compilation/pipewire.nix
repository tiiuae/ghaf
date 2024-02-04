# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  # It defaulted to
  # { ...
  # , x11Support ? true
  # , ffadoSupport ? x11Support && stdenv.buildPlatform.canExecute stdenv.hostPlatform
  # }
  # It should evaluate to `false` in case of cross-compilation, but it doesn't happens for unknown reasons.
  pipewire = prev.pipewire.override {ffadoSupport = false;};
})
