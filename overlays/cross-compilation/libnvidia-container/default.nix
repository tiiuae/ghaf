# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# libnvidia-container cross-compilation fixes
#
{ prev }:
prev.libnvidia-container.overrideAttrs (old: {
  # preBuild section for verbosity and debug only  
  preBuild =
    old.preBuild
    + ''
      echo ------
      echo $OBJCOPY
      echo $PKG_CONFIG
      echo $PKG_CONFIG_PATH
      echo ------
      go env
      echo ------
    '';
  postPatch =
    old.postPatch
    + ''
      sed -i Makefile \
        -e "s,pkg-config,$PKG_CONFIG,g"
      sed -i mk/common.mk \
        -e "s,objcopy,$OBJCOPY,g" \
        -e "s,ldconfig,true,g"
    '';
  env = old.env // {
    inherit (prev.go) GOARCH GOOS;
    CGO_ENABLED = "1";
    GOFLAGS = "-trimpath";
  };
  depsBuildBuild = [
    prev.pkg-config
  ];
})
