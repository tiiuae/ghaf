# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, systemd }:
(systemd.override {
  withDocumentation = false;
  withLibBPF = false;
}).overrideAttrs
  (old: {
    pname = "ghaf-journal-remote";
    patches = (old.patches or [ ]) ++ [ ./authenticated-source.patch ];
    # Nixpkgs disables the upstream HTTPS receiver by default.
    mesonFlags = lib.filter (flag: !(lib.hasPrefix "-Dgnutls=" flag)) old.mesonFlags ++ [
      "-Dgnutls=enabled"
    ];
    outputs = [ "out" ];
    separateDebugInfo = false;
    buildPhase = ''
      runHook preBuild
      ninja -j"$NIX_BUILD_CORES" systemd-journal-remote
      runHook postBuild
    '';
    installPhase = ''
      install -Dm755 systemd-journal-remote $out/bin/systemd-journal-remote
      install -d $out/lib/systemd
      install -m755 src/shared/libsystemd-shared-*.so $out/lib/systemd/
    '';
    postFixup = "";
    doInstallCheck = false;
    meta = old.meta // {
      description = "Native systemd journal receiver with HTTPS support";
      mainProgram = "systemd-journal-remote";
    };
  })
