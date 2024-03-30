# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{inputs, ...}: {
  imports = with inputs; [
    flake-root.flakeModule
    ./devshell/kernel.nix
    # TODO this import needs to be filtered to remove RISCV
    # pre-commit-hooks-nix.flakeModule
  ];
  perSystem = {
    pkgs,
    inputs',
    self',
    lib,
    system,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      name = "Ghaf devshell";
      #TODO look at adding Mission control etc here
      packages = with pkgs;
        [
          git
          nix
          nixci
          nixos-rebuild
          reuse
          alejandra
          mdbook
          inputs'.nix-fast-build.packages.default
          self'.packages.kernel-hardening-checker
        ]
        ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") cachix;

      # TODO Add pre-commit.devShell (needs to exclude RiscV)
      # https://flake.parts/options/pre-commit-hooks-nix
    };
  };
}
