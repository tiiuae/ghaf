# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf-specific QEMU package with ivshmem, TPM, USB, and ACPI patches.
# Standalone package so it can be built and tested without NixOS evaluation:
#   nix build .#ghaf-qemu
#
{
  lib,
  stdenv,
  qemu_kvm,
  ...
}:
qemu_kvm.overrideAttrs (
  _final: prev: {
    patches =
      prev.patches
      ++ [
        # Shared memory support for inter-VM communication
        ./patches/0001-ivshmem-flat-memory-support.patch
        # Increase TPM command timeout
        ./patches/0002-Increase-timeout-in-tpm_util_request.patch
        # USB host autoscan for bus/addr passthrough
        ./patches/usb-host-enable-autoscan-for-bus-addr.patch
      ]
      ++ lib.optionals stdenv.hostPlatform.isx86_64 [
        # ACPI battery/power management for VMs
        # https://github.com/blochl/qemu/pull/3
        # TODO: remove when merged upstream
        ./patches/0001-hw-acpi-Support-extended-GPE-handling-for-additional.patch
        ./patches/0002-hw-acpi-Introduce-the-QEMU-Battery.patch
        ./patches/0003-hw-acpi-Introduce-the-QEMU-AC-adapter.patch
        ./patches/0004-hw-acpi-Introduce-the-QEMU-lid-button.patch
      ];

    postInstall = (prev.postInstall or "") + ''
      cp contrib/ivshmem-server/ivshmem-server $out/bin
    '';
  }
)
