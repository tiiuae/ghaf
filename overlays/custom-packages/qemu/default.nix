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
    patches = prev.patches ++ [
      ./acpi-devices-passthrough-qemu-8.1.patch
      ./0001-ivshmem-flat-memory-support.patch
    ];
  })
  // {
    postInstall =
      (prev.postInstall or "")
      + ''
        cp contrib/ivshmem-server/ivshmem-server $out/bin
      '';
    # Design defence: we need to permit evaluate 'vfio-pci,host=$(some-script)' statements, and forbid evaluating other arguments
    # Only way to do it without heavy patching of microvm itself -- inject wrapper into qemu package via overlaying
    postFixup =
      (prev.postFixup or "")
      + ''
        injectQemuWrapper() {
            local prog="$1"
            local wrapper="$2"
            local hidden

            assertExecutable "$prog"

            # Renaming borrowed from wrapProgramShell() of nixpkgs
            hidden="$(dirname "$prog")/.$(basename "$prog")"-wrapped
            while [ -e "$hidden" ]; do
              hidden="''${hidden}_"
            done
            mv "$prog" "$hidden"

            install -m0755 $wrapper $prog
            substituteInPlace "$prog" \
                --replace-fail "/bin/bash" "${final.runtimeShell}" \
                --replace-fail "@UNWRAPPED@" "$hidden"
        }
        set -x
        for each in $out/bin/qemu-system-*; do
            injectQemuWrapper "$each" "${./wrapper.sh}"
        done
        set +x
      '';
  }
)
