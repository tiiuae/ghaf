# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# waypipe does not cross-compile out of the box (aarch64-from-x86_64). Three
# independent gaps, all in how its meson wrapper drives cargo:
#
#   1. meson.build does `find_program('objcopy', native: true)`, but the
#      derivation ships no plain `objcopy`; native builds find it via the
#      stdenv cc-wrapper, a cross build does not. Put the toolchain objcopy on
#      PATH under the unprefixed name.
#   2. compile_wrapper.sh runs a bare `cargo build` (no --target). Cargo
#      cross-builds via CARGO_BUILD_TARGET, but rustc then defaults its linker
#      to the native `cc`, so aarch64 objects get linked with the x86 ld
#      ("skipping incompatible ..."). Point cargo at the target linker.
#   3. With CARGO_BUILD_TARGET set, cargo writes the binary under
#      target/<triple>/<profile>/, but compile_wrapper.sh copies from
#      target/<profile>/. Insert the triple subdir when cross.
#
# All harmless for native builds.
{ prev }:
let
  inherit (prev) stdenv lib;
  cross = stdenv.hostPlatform != stdenv.buildPlatform;
in
prev.waypipe.overrideAttrs (
  old:
  {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ stdenv.cc.bintools ];
    preConfigure = (old.preConfigure or "") + ''
      mkdir -p "$TMPDIR/objcopy-shim"
      ln -sf "$(command -v ${stdenv.cc.targetPrefix}objcopy)" "$TMPDIR/objcopy-shim/objcopy"
      export PATH="$TMPDIR/objcopy-shim:$PATH"
    '';
  }
  // lib.optionalAttrs cross {
    # compile_wrapper.sh runs a bare `cargo build`; without an explicit target
    # cargo ignores CARGO_TARGET_<triple>_LINKER and links with the native cc.
    # Naming the target makes the linker env apply and moves the output under
    # target/<triple>/ (handled by the postPatch cp below).
    CARGO_BUILD_TARGET = stdenv.hostPlatform.rust.rustcTarget;
    "CARGO_TARGET_${stdenv.hostPlatform.rust.cargoEnvVarTarget}_LINKER" = "${stdenv.cc.targetPrefix}cc";
    postPatch = (old.postPatch or "") + ''
      substituteInPlace compile_wrapper.sh \
        --replace-fail 'cp "$3/$1/waypipe" "$5"' \
          'cp "$3/''${CARGO_BUILD_TARGET:+$CARGO_BUILD_TARGET/}$1/waypipe" "$5"'
    '';
  }
)
