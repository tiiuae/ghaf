# Copyright 2023-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  final,
  prev,
}:
(
  prev.pipewire.override {
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
