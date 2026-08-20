# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# waypipe does not cross-compile out of the box (aarch64-from-x86_64). Three
# independent gaps, all in how its meson wrapper drives cargo. Those fixes are
# cross-only, so a native build's derivation is nixpkgs' unchanged.
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
# Native builds are left entirely alone.
{ prev }:
let
  inherit (prev) stdenv lib;
  cross = stdenv.hostPlatform != stdenv.buildPlatform;
in
prev.waypipe.overrideAttrs (
  old:
  lib.optionalAttrs cross {
    # Native builds already find objcopy through the stdenv cc-wrapper, so this
    # whole block is cross-only. Applying it unconditionally changed waypipe's
    # derivation hash for every target -- x86 laptops included -- to fix a
    # problem only the cross build has.
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ stdenv.cc.bintools ];
    preConfigure = (old.preConfigure or "") + ''
      if ! objcopy_bin="$(command -v ${stdenv.cc.targetPrefix}objcopy)"; then
        echo "waypipe overlay: ${stdenv.cc.targetPrefix}objcopy not on PATH" >&2
        exit 1
      fi
      mkdir -p "$TMPDIR/objcopy-shim"
      ln -sf "$objcopy_bin" "$TMPDIR/objcopy-shim/objcopy"
      export PATH="$TMPDIR/objcopy-shim:$PATH"
    '';

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
