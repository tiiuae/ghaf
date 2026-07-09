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

  # Remove gfortran from FFTW to avoid cross-compiling the entire Fortran
  # toolchain. FFTW is pulled in by PipeWire for audio processing. The Fortran
  # wrapper generation is only needed when building docs (--disable-doc already
  # strips the Fortran codegen step). Ghaf does not use the Fortran bindings.
  fftwFloat = prev.fftwFloat.overrideAttrs (oldAttrs: {
    nativeBuildInputs = builtins.filter (d: !(final.lib.hasPrefix "gfortran" (d.pname or ""))) (
      oldAttrs.nativeBuildInputs or [ ]
    );
  });

  # Fix for libqmi cross-compilation.
  # libqmi 1.38 switched from gtk-doc to gi-docgen for documentation.
  # gi-docgen looks up its dependency via build-machine pkg-config,
  # which is not available during cross-compilation
  # Disable documentation generation to unblock the build
  libqmi = prev.libqmi.overrideAttrs (oldAttrs: {
    mesonFlags = map (f: if f == "-Dgtk_doc=true" then "-Dgtk_doc=false" else f) (
      oldAttrs.mesonFlags or [ ]
    );
    nativeBuildInputs = builtins.filter (d: (d.pname or "") != "gi-docgen") (
      oldAttrs.nativeBuildInputs or [ ]
    );
  });

})
# keep-sorted end
