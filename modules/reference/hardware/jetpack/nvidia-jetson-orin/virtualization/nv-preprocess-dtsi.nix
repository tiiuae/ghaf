# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Utility function to compile a device tree source file (dts/dtsi) to a device tree binary (dtbo)
# using the include paths to resolve Tegra-specific symbols (TEGRA234_*).
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  dtsTree = config.hardware.deviceTree.dtbSource.src;

  bspIncludePaths = [
    # SOC independent common include
    "${dtsTree}/hardware/nvidia/tegra/nv-public"
    "${dtsTree}/hardware/nvidia/tegra/nv-public/include/kernel"
    "${dtsTree}/hardware/nvidia/tegra/nv-public/include/nvidia-oot"
    "${dtsTree}/hardware/nvidia/tegra/nv-public/include/platforms"
    # SOC T23X specific common include
    "${dtsTree}/hardware/nvidia/t23x/nv-public/include/kernel"
    "${dtsTree}/hardware/nvidia/t23x/nv-public/include/nvidia-oot"
    "${dtsTree}/hardware/nvidia/t23x/nv-public/include/platforms"
    "${dtsTree}/hardware/nvidia/t23x/nv-public"
    # - t264 includes omitted -
  ];

  preprocessDtsi =
    {
      dtsFile,
      name ? "${lib.head (lib.splitString "." (baseNameOf (toString dtsFile)))}.dtbo",
      includePaths ? [ ],
      extraPreprocessorFlags ? [ ],
    }:
    pkgs.deviceTree.compileDTS {
      includePaths = includePaths ++ bspIncludePaths;
      inherit name dtsFile extraPreprocessorFlags;
    };
in
{
  lib.jetpack.preprocessDtsi = preprocessDtsi;
}
