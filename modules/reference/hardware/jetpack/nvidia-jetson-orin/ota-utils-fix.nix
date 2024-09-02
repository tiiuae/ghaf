# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for fixing ota-utils.
#
# There is upstream PR waiting for review:
# https://github.com/anduril/jetpack-nixos/pull/162
#
{ pkgs, lib, ... }:
{
  # mkAfter needed here so that we can be sure the overlay is after the overlay
  # included from jetpack-nixos. Otherwise it will just override the whole
  # nvidia-jetpack set.
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      nvidia-jetpack = prev.nvidia-jetpack // {
        otaUtils = prev.nvidia-jetpack.otaUtils.overrideAttrs (
          _finalAttrs: prevAttrs: {
            depsBuildHost = [ pkgs.bash ];
            installPhase =
              prevAttrs.installPhase
              + ''
                substituteInPlace $out/bin/* --replace '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
              '';
          }
        );
      };
    })
  ];
}
