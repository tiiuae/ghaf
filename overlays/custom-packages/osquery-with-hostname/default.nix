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
  # osquery's eBPF component (ebpfpub) is not needed for the Orin gui-vm
  # telemetry and does not cross-compile:
  #  - disable BPF so ebpfpub is not linked into osqueryd;
  #  - ebpf-common's LLVM cmake still gets configured during the third-party
  #    import and requests `x86codegen` (it reads the host CMAKE_SYSTEM_PROCESSOR),
  #    which the aarch64-only osquery-toolchain LLVM omits -> a fatal
  #    LLVM-Config error before the BPF-off fallback can run. Request the codegen
  #    that LLVM actually has so configure completes.
  cmakeFlags = (old.cmakeFlags or [ ]) ++ lib.optionals aarch64Target [ "-DOSQUERY_BUILD_BPF=OFF" ];

  postPatch =
    (old.postPatch or "")
    + lib.optionalString aarch64Target ''
      substituteInPlace libraries/cmake/source/ebpfpub/src/libraries/ebpf-common/src/libraries/LLVM/CMakeLists.txt \
        --replace-fail 'list(APPEND llvm_component_list x86codegen)' \
          'list(APPEND llvm_component_list aarch64codegen)'

      # globals.cmake derives TARGET_PROCESSOR from CMAKE_SYSTEM_PROCESSOR, but
      # in this cross setup the vendored boost still ended up compiling the
      # x86_64 boost.context assembly with the aarch64 clang. Force the target
      # architecture outright; every consumer (asm selection, per-arch source
      # lists) keys off TARGET_PROCESSOR.
      sed -i 's/set(TARGET_PROCESSOR "x86_64")/set(TARGET_PROCESSOR "aarch64")/' \
        cmake/globals.cmake
    '';
})
