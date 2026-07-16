# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# overlays/custom-packages/cosmic/cosmic-comp/default.nix

{ prev }:
# let
#   gbm-nomod-shim = prev.runCommandCC "gbm-nomod-shim" { } ''
#     mkdir -p $out/lib
#     $CC -O2 -fPIC -shared -o $out/lib/gbm-nomod-shim.so \
#       ${./sources/gbm-nomod-shim.c} -ldl
#   '';
# in
prev.cosmic-comp.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Add-security-context-indicator.patch
    ./0002-Disable-VRR-by-default.patch
    ./0003-cosmic-comp-egl-device.patch
    ./0005-cosmic-comp-egl-device-optional.patch
    ./0006-cosmic-comp-nvidia-software-cursor.patch
    ./0007-cosmic-comp-tegra-dmabuf-fence-poll.patch
  ];

  cargoPatches = (oldAttrs.cargoPatches or []) ++ [
    ./0004-Disable-EGL-enumeration.patch
  ];

  # nativeBuildInputs =
  #   (oldAttrs.nativeBuildInputs or [])
  #   ++ [ prev.buildPackages.makeWrapper ];

  # postFixup = (oldAttrs.postFixup or "") + ''
  #   wrapProgram $out/bin/cosmic-comp \
  #     --set LD_PRELOAD ${gbm-nomod-shim}/lib/gbm-nomod-shim.so
  # '';
})