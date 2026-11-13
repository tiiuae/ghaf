# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ prev }:
let
  inherit (prev) stdenv lib;
  # Keyed on the TARGET, not on cross-ness, so a given target gets the same
  # osquery whichever machine built it.
  aarch64Target = stdenv.hostPlatform.isAarch64;
in
prev.osquery.overrideAttrs (old: {
  pname = "osquery-with-hostname";
  patches = (old.patches or [ ]) ++ [
    ./hostname-file.patch
  ];
  postPatch =
    (old.postPatch or "")
    + lib.optionalString aarch64Target ''
      # osquery 5.24.1 restored ebpfpub and added a BPF-based linuxevents
      # experiment. Both vendor ebpf-common, whose LLVM cmake asks for the
      # x86codegen that the aarch64 osquery-toolchain LLVM omits, and BPF
      # telemetry is unused in the Orin gui-vm. nixpkgs writes its own cmake
      # call and drops cmakeFlags, so both options are flipped where declared.
      substituteInPlace cmake/options.cmake \
        --replace-fail \
          'option(OSQUERY_BUILD_BPF "Whether to enable and build BPF support" ON)' \
          'option(OSQUERY_BUILD_BPF "Whether to enable and build BPF support" OFF)' \
        --replace-fail \
          'option(OSQUERY_BUILD_EXPERIMENTS "Whether to build experiments" ON)' \
          'option(OSQUERY_BUILD_EXPERIMENTS "Whether to build experiments" OFF)'

      # globals.cmake derives TARGET_PROCESSOR from CMAKE_SYSTEM_PROCESSOR, but
      # in this cross setup the vendored boost still ended up compiling the
      # x86_64 boost.context assembly with the aarch64 clang. Force the target
      # architecture outright; every consumer (asm selection, per-arch source
      # lists) keys off TARGET_PROCESSOR.
      sed -i 's/set(TARGET_PROCESSOR "x86_64")/set(TARGET_PROCESSOR "aarch64")/' \
        cmake/globals.cmake
    '';
})
