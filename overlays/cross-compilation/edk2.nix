# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# edk2 & OVMF cross-compilation fixes
#
(final: prev: {
  edk2 = prev.edk2.overrideAttrs (oa: {
    # Fix cross-compilation issue, use build cc/c++ for building antlr and dlg
    postPatch =
      (oa.postPatch or "")
      + ''
        substituteInPlace BaseTools/Source/C/VfrCompile/GNUmakefile \
          --replace '$(MAKE) -C Pccts/antlr' '$(MAKE) -C Pccts/antlr CC=cc CXX=c++' \
          --replace '$(MAKE) -C Pccts/dlg' '$(MAKE) -C Pccts/dlg CC=cc CXX=c++'
      '';
    passthru = {
      mkDerivation = dsc: fun:
        oa.passthru.mkDerivation dsc (finalAttrs:
          {
            prePatch = ''
              echo "prePatch hooked!"
              rm -rf BaseTools
              ln -sv ${final.buildPackages.edk2}/BaseTools BaseTools
            '';

            configurePhase = ''
              echo "configurePhase hooked"
              runHook preConfigure
              export WORKSPACE="$PWD"
              . ${final.buildPackages.edk2}/edksetup.sh BaseTools
              runHook postConfigure
            '';
          }
          // fun finalAttrs);
    };
  });
})
