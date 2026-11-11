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
  # osquery 5.24 removed ebpfpub and OSQUERY_BUILD_BPF; dropping the obsolete
  # BPF-off workaround does not enable the removed eBPF event component.
  postPatch =
    (old.postPatch or "")
    + lib.optionalString aarch64Target ''
      # globals.cmake derives TARGET_PROCESSOR from CMAKE_SYSTEM_PROCESSOR, but
      # in this cross setup the vendored boost still ended up compiling the
      # x86_64 boost.context assembly with the aarch64 clang. Force the target
      # architecture outright; every consumer (asm selection, per-arch source
      # lists) keys off TARGET_PROCESSOR.
      sed -i 's/set(TARGET_PROCESSOR "x86_64")/set(TARGET_PROCESSOR "aarch64")/' \
        cmake/globals.cmake
    '';
})
