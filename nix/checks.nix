# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
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
      }
      // (lib.mapAttrs' (n: lib.nameValuePair "package-${n}") self'.packages);
  };
}
