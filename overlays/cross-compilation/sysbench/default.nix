# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Sysbench cross-compilation fixes
#
{
  final,
  prev,
}:
prev.sysbench.overrideAttrs (old: {
  configureFlags = [
    "--with-system-luajit"
    "--with-system-ck"
    "--with-mysql-includes=${prev.lib.getDev final.libmysqlclient}/include/mysql"
    "--with-mysql-libs=${final.libmysqlclient}/lib/mysql"
  ];
  buildInputs = old.buildInputs ++ [final.libck];
  depsBuildBuild = [final.pkg-config];
})
