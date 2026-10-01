# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
pkgs.runCommand "installer-secureboot-test"
  {
    nativeBuildInputs = with pkgs; [
      binutils-unwrapped
      efitools
      (callPackage ../../packages/pkgs-by-name/ghaf-verify-enrollment/package.nix { })
      openssl
      sbsigntool
    ];
    BOOT_LIB = ../../lib/installer-boot-lib.sh;
    EFI_LOADER = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-bootx64.efi";
    EFI_STUB = "${pkgs.systemd}/lib/systemd/boot/efi/linuxx64.efi.stub";
  }
  ''
    bash ${./secureboot.sh}
    touch "$out"
  ''
