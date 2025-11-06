# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  lib,
  stdenv,
  writeShellApplication,
}:
let
  process-audit-rules = writeShellApplication {
    name = "process-audit-rules";
    runtimeInputs = [ coreutils ];
    text = builtins.readFile ./process-audit-rules.sh;
  };
in
stdenv.mkDerivation {
  name = "audit-rules";
  version = "0.1";

  runtimeInputs = [
    coreutils
  ];

  src = fetchGit {
    url = "https://github.com/linux-audit/audit-userspace";
    rev = "e0ee54633d663a7b0ccadca15f2a5d74997e6cbc";
    narHash = "sha256-MWlHaGue7Ca8ks34KNg74n4Rfj8ivqAhLOJHeyE2Q04=";
  };

  installPhase = ''
    mkdir -p $out/share/audit/rules
    ${lib.getExe process-audit-rules} $src/rules/ $out/share/audit/rules/
  '';

  meta = {
    description = "Script to transform auditd rule files to nix formatted files";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    license = lib.licenses.asl20;
  };
}
