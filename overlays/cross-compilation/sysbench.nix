# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
(final: prev: {
  libck = prev.libck.overrideAttrs (old: {
    postPatch = ''
      substituteInPlace \
        configure \
          --replace \
            'COMPILER=`./.1 2> /dev/null`' \
            "COMPILER=gcc"
    '';
    configureFlags = ["--platform=${prev.stdenv.hostPlatform.parsed.cpu.name}}"];
  });
  sysbench = prev.sysbench.overrideAttrs (old: {
    configureFlags = [
      "--with-system-luajit"
      "--with-system-ck"
      "--with-mysql-includes=${prev.lib.getDev final.libmysqlclient}/include/mysql"
      "--with-mysql-libs=${final.libmysqlclient}/lib/mysql"
    ];
    buildInputs = old.buildInputs ++ [final.libck];
    depsBuildBuild = [final.pkg-config];
  });
})
