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

  # Fix qt5ct cross-compilation.
  # qt5ct pulls in qttools as a nativeBuildInput purely to compile optional
  # translation (.qm) files via lrelease. qttools propagates a build-platform
  # qtbase, which brings in that qtbase's setup hook alongside the one from
  # the (cross) qtbase already in buildInputs. Both hooks set/check the same
  # "$__nix_qtbase" marker, and since the two qtbase paths differ when
  # cross-compiling, the second hook aborts with "detected mismatched Qt
  # dependencies". Dropping qttools loses translations (English-only UI) but
  # is otherwise harmless, since qt5ct only needs it for lrelease.
  libsForQt5 = prev.libsForQt5.overrideScope (
    _lfinal: lprev: {
      qt5ct = lprev.qt5ct.overrideAttrs (oldAttrs: {
        nativeBuildInputs = builtins.filter (d: (d.pname or "") != "qttools") (
          oldAttrs.nativeBuildInputs or [ ]
        );
      });
    }
  );

  # tpm2-pytss 3.0.0rc1 already invokes $CC -E when preprocessing headers,
  # so nixpkgs' older cross.patch no longer applies and is no longer needed.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pythonFinal: pythonPrev: {
      tpm2-pytss = pythonPrev.tpm2-pytss.overrideAttrs (
        oldAttrs:
        final.lib.optionalAttrs (oldAttrs.version == "3.0.0rc1") {
          patches = builtins.filter (patch: !(final.lib.hasSuffix "cross.patch" (toString patch))) (
            oldAttrs.patches or [ ]
          );
        }
      );
    })
  ];

  # Fix qt6ct cross-compilation, same cause and fix as qt5ct above: qttools
  # is only needed for optional translations (CMake's LinguistTools).
  qt6Packages = prev.qt6Packages.overrideScope (
    _qfinal: qprev: {
      qt6ct = qprev.qt6ct.overrideAttrs (oldAttrs: {
        nativeBuildInputs = builtins.filter (d: (d.pname or "") != "qttools") (
          oldAttrs.nativeBuildInputs or [ ]
        );
      });
    }
  );

  # Fix swtpm cross-compilation.
  # swtpm 0.10.1-unstable-2026-05-21 switched its local CA from gnutls certtool
  # to the openssl CLI, so configure.ac now does AC_PATH_PROG([OPENSSL], ...)
  # and aborts when the tool is absent:
  #   configure: error: "Could not find openssl tool. Is openssl installed?"
  # nixpkgs only lists openssl in buildInputs. Natively that still works, since
  # build == host means the buildInputs bin dirs land on PATH anyway, but when
  # cross-compiling they go to HOST_PATH instead and configure sees nothing.
  # A build-platform openssl is what the configure probe actually wants
  # (openssl's default output is "bin", so this puts the CLI on PATH).
  swtpm = prev.swtpm.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ final.buildPackages.openssl ];
  });

})
# keep-sorted end
