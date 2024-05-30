# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  final,
  prev,
}:
prev.crosvm.overrideAttrs (_final: prevAttrs: rec {
  version = "122.1";
  src = prev.fetchgit {
    url = "https://chromium.googlesource.com/chromiumos/platform/crosvm";
    rev = "562d81eb28a49ed6e0d771a430c21a458cdd33f9";
    sha256 = "sha256-l5sIUInOhhkn3ernQLIEwEpRCyICDH/1k4C/aidy1/I=";
    fetchSubmodules = true;
  };

  patches = [];

  cargoBuildFeatures = final.lib.lists.remove "virgl_renderer_next" prevAttrs.cargoBuildFeatures;
  cargoCheckFeatures = final.lib.lists.remove "virgl_renderer_next" prevAttrs.cargoCheckFeatures;
  CROSVM_USE_SYSTEM_MINIGBM = true;

  cargoDeps = prevAttrs.cargoDeps.overrideAttrs (prev.lib.const {
    inherit src;
    name = "crosvm-vendor.tar.gz";
    outputHash = "sha256-yTdho6lW+XqB/iGf+bT2iwnAdjz3TrrI7YAaLoenR1U=";
  });
})
