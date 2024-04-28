# Copyright 2023-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  final,
  prev,
}:
# It defaulted to
# { ...
# , x11Support ? true
# , ffadoSupport ? x11Support && stdenv.buildPlatform.canExecute stdenv.hostPlatform
# }
# It should evaluate to `false` in case of cross-compilation, but it doesn't happens for unknown reasons.
(
  prev.pipewire.override {
    ffadoSupport = false;
    #TODO review the use of libcamera as if causes a lot of FOD errors
    libcameraSupport = false;
  }
)
#TODO remove this when we upgrade to mainline for 24.05
#SEE https://github.com/NixOS/nixpkgs/issues/293060
.overrideAttrs (
  old: {
    buildInputs = old.buildInputs ++ [final.libdrm];
  }
)
