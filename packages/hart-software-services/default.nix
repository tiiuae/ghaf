# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  fetchFromGitHub,
  lib,
  python3,
  stdenv,
}:
let
  version = "v2022.09";
in
stdenv.mkDerivation (
  {
    pname = "hart-software-services";
    inherit version;

    src = fetchFromGitHub {
      owner = "polarfire-soc";
      repo = "hart-software-services";
      rev = version;
      sha256 = "sha256-j/nda7//CjJW09zt/YrBy6h+q+VKE5t/ueXxDzwVWQ0=";
    };

    patches = [ ./0001-Workaround-for-a-compilation-issue.patch ];
    depsBuildBuild = [ python3 ];

    configurePhase = ''
      runHook preConfigure

      cp boards/mpfs-icicle-kit-es/def_config .config

      runHook postConfigure
    '';

    makeFlags = [
      "V=1"
      "BOARD=mpfs-icicle-kit-es"
      "PLATFORM_RISCV_ABI=lp64d"
      "PLATFORM_RISCV_ISA=rv64imadc_zicsr_zifencei"
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp Default/*.elf Default/*.bin $out/

      runHook postInstall
    '';
  }
  // lib.optionalAttrs (stdenv.buildPlatform.system != stdenv.hostPlatform.system) {
    CROSS_COMPILE = stdenv.cc.targetPrefix;
  }
)
