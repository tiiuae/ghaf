# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ final, prev }:
let
  qemu_version = prev.qemu_kvm.version;
in
prev.qemu_kvm.overrideAttrs (
  _final: prev:
  (final.lib.optionalAttrs (final.lib.versionAtLeast qemu_version "10.1") {
    patches =
      prev.patches
      ++ [
        # own patches
        ./0001-ivshmem-flat-memory-support.patch
        ./0002-Increase-timeout-in-tpm_util_request.patch
        ./usb-host-enable-autoscan-for-bus-addr.patch
      ]
      ++ final.lib.optionals final.stdenv.hostPlatform.isx86_64 [
        # https://github.com/blochl/qemu/pull/3
        # TODO: remove when merged upstream
        ./0001-hw-acpi-Support-extended-GPE-handling-for-additional.patch
        ./0002-hw-acpi-Introduce-the-QEMU-Battery.patch
        ./0003-hw-acpi-Introduce-the-QEMU-AC-adapter.patch
        ./0004-hw-acpi-Introduce-the-QEMU-lid-button.patch
      ];
  })
  // {
    postInstall = (prev.postInstall or "") + ''
      cp contrib/ivshmem-server/ivshmem-server $out/bin
    '';
  }
)
