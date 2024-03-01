# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# libck cross-compilation fixes
#
{prev}:
prev.libck.overrideAttrs (_old: {
  postPatch = ''
    substituteInPlace \
      configure \
        --replace \
          'COMPILER=`./.1 2> /dev/null`' \
          "COMPILER=gcc"
  '';
  configureFlags = ["--platform=${prev.stdenv.hostPlatform.parsed.cpu.name}}"];
})
