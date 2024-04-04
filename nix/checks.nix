# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: {
    checks =
      {
        reuse =
          pkgs.runCommandLocal "reuse-lint" {
            buildInputs = [pkgs.reuse];
          } ''
            cd ${../.}
            reuse lint
            touch $out
          '';
        module-test-hardened-generic-host-kernel =
          pkgs.callPackage ../modules/hardware/x86_64-generic/kernel/host/test {inherit pkgs;};
        module-test-hardened-lenovo-x1-guest-guivm-kernel =
          pkgs.callPackage ../modules/hardware/lenovo-x1/kernel/guest/test {inherit pkgs;};
        module-test-hardened-pkvm-kernel =
          pkgs.callPackage ../modules/hardware/x86_64-generic/kernel/host/pkvm/test {inherit pkgs;};
      }
      // (lib.mapAttrs' (n: lib.nameValuePair "package-${n}") self'.packages);
  };
}
