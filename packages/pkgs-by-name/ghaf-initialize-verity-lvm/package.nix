# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  writeShellApplication,
  coreutils,
  util-linux,
  lvm2,
  cryptsetup,
  btrfs-progs,
  zstd,
  jq,
  ghaf-update-manifest,
}:
let
  initializer = writeShellApplication {
    name = "ghaf-initialize-verity-lvm";
    runtimeInputs = [
      coreutils
      util-linux
      lvm2
      cryptsetup
      btrfs-progs
      zstd
      jq
      ghaf-update-manifest
    ];
    text = builtins.readFile ./initialize.sh;
    meta = {
      description = "Create Ghaf A/B volumes on a disposable build-VM disk";
      mainProgram = "ghaf-initialize-verity-lvm";
      platforms = lib.platforms.linux;
    };
  };
in
initializer.overrideAttrs (_: {
  passthru.tests.vm = import ./test.nix { inherit pkgs initializer ghaf-update-manifest; };
})
