# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  _file = ./secure-ab-x86.nix;

  # Enrollment material is supplied alongside the externally signed image.
  # Keeping keysSource null prevents even public enrollment payloads from
  # accidentally selecting a repository trust set different from the signer.
  ghaf.host.secureboot = {
    enable = true;
    keysSource = lib.mkForce null;
  };

  ghaf.storage.encryption.deferred = lib.mkForce false;

  # A Type-2 UKI authenticates its command line, so allowing interactive edits
  # would be both ineffective and misleading.
  boot.loader.systemd-boot.editor = false;
  boot.kernelParams = [
    "boot.panic_on_fail"
    "panic=10"
  ];
}
