# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ final, prev }:
let
  qemu_version = prev.qemu_kvm.version;
  qemu_major = final.lib.versions.major qemu_version;
  qemu_minor = final.lib.versions.minor qemu_version;
in
prev.qemu_kvm.overrideAttrs (
  _final: prev:
  (final.lib.optionalAttrs (qemu_major == "8" && qemu_minor == "0") {
    patches = prev.patches ++ [ ./acpi-devices-passthrough-qemu-8.0.patch ];
  })
  // (final.lib.optionalAttrs (final.lib.versionAtLeast qemu_version "8.1") {
    patches = prev.patches ++ [ ./acpi-devices-passthrough-qemu-8.1.patch ];
  })
)
