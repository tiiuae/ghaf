# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
# keep-sorted start skip_lines=1 block=yes newline_separated=yes
(final: prev: {
  # cosmic-reader add missing pkg-config nativeBuildInput dependency
  cosmic-reader = prev.cosmic-reader.overrideAttrs (oldAttrs: {
    nativeBuildInputs =
      (oldAttrs.nativeBuildInputs or [ ])
      ++ final.lib.optionals (
        !builtins.any (p: (p.pname or "") == "pkg-config") (oldAttrs.nativeBuildInputs or [ ])
      ) [ final.buildPackages.pkg-config ];
  });

  execline = prev.execline.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
      final.buildPackages.buildPackages.pkg-config
    ];
  });

  # Remove gfortran from FFTW to avoid cross-compiling the entire Fortran
  # toolchain. FFTW is pulled in by PipeWire for audio processing. The Fortran
  # wrapper generation is only needed when building docs (--disable-doc already
  # strips the Fortran codegen step). Ghaf does not use the Fortran bindings.
  fftwFloat = prev.fftwFloat.overrideAttrs (oldAttrs: {
    nativeBuildInputs = builtins.filter (d: !(final.lib.hasPrefix "gfortran" (d.pname or ""))) (
      oldAttrs.nativeBuildInputs or [ ]
    );
  });

  # tpm2-pytss 3.0.0rc1 already invokes $CC -E when preprocessing headers,
  # so nixpkgs' older cross.patch no longer applies and is no longer needed.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pythonFinal: pythonPrev: {
      tpm2-pytss = pythonPrev.tpm2-pytss.overrideAttrs (
        oldAttrs:
        final.lib.optionalAttrs (oldAttrs.version == "3.0.0") {
          patches = builtins.filter (patch: !(final.lib.hasSuffix "cross.patch" (toString patch))) (
            oldAttrs.patches or [ ]
          );
        }
      );
    })
  ];

  s6 = (prev.s6.override { inherit (final) execline; }).overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
      final.buildPackages.buildPackages.pkg-config
    ];
  });

})
# keep-sorted end
