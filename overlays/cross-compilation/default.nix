# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
# Native target imports must retain Ghaf overlays without these build-only fixes.
#
(
  final: prev:
  prev.lib.optionalAttrs (prev.stdenv.buildPlatform != prev.stdenv.hostPlatform) {
    # keep-sorted start block=yes newline_separated=yes
    # `go` is spliced build->target here, so GO_EXTLINK_ENABLED=1 is baked into it
    # and the cmake code generators link their amd64 objects with the cross CC,
    # which rejects -m64. Keep the generators pure Go and internally linked.
    aws-lc = prev.aws-lc.overrideAttrs (oldAttrs: {
      env = (oldAttrs.env or { }) // {
        CGO_ENABLED = "0";
        GOFLAGS = "-ldflags=-linkmode=internal";
      };
    });

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

    # nixpkgs enables introspection whenever an emulator exists but never adds
    # mesonEmulatorHook, so meson's can_run_host_binaries() check aborts. Our only
    # consumer, libadwaita, vendors ministream with introspection=disabled anyway.
    ministream = prev.ministream.override { withIntrospection = false; };

    packagekit = prev.packagekit.overrideAttrs (oldAttrs: {
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ final.buildPackages.python3 ];
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

    # keep-sorted end
  }
  // prev.lib.optionalAttrs (prev.stdenv.targetPlatform != prev.stdenv.hostPlatform) {
    # bindgen is a native build input, so it comes from pkgsBuildHost where only
    # targetPlatform marks the cross. nixpkgs takes --target from targetPlatform
    # but its include flags from rustc's clang, which there is the x86_64 one.
    rust-bindgen-unwrapped = prev.rust-bindgen-unwrapped.overrideAttrs (oldAttrs: {
      passthru = (oldAttrs.passthru or { }) // {
        # llvmPackages_23 is what rustc pins, so bindgen keeps its own libclang.
        clang = final.llvmPackages_23.clang;
      };
    });
  }
)
