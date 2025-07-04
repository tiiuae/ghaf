# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay ensures that jetpack-nixos's CUDA packages are used
# instead of the default nixpkgs CUDA packages, which prevents
# version mismatch issues (JetPack 5 uses CUDA 11.4)
#
_final: prev:
# Only override cudaPackages if nvidia-jetpack exists in prev
if prev ? nvidia-jetpack then
  {
    # Use CUDA packages from nvidia-jetpack
    inherit (prev.nvidia-jetpack) cudaPackages;
  }
else
  { }
