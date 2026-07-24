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

  # Fix systemd BPF framework cross-compilation.
  # systemd moved find_program('clang', ...) out of the top-level meson.build
  # into src/bpf/meson.build. nixpkgs still substitutes the target-prefixed
  # clang into the old path with a plain --replace, so the substitution
  # silently became a no-op and the BPF objects get compiled by the unwrapped
  # build-platform clang, which carries no target include paths:
  #   libbpf/include/linux/bpf.h:11:10: fatal error: 'linux/types.h' file not found
  # Fixed upstream by https://github.com/NixOS/nixpkgs/pull/540766, merged to
  # staging. Drop this once that reaches the nixpkgs pin - it uses
  # --replace-fail, so it will fail loudly rather than silently no-op.
  systemd = prev.systemd.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace src/bpf/meson.build \
        --replace-fail "find_program('clang'" "find_program('${prev.stdenv.cc.targetPrefix}clang'"
    '';
  });

})
# keep-sorted end
