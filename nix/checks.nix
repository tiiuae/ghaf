# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      # Checks are automatically provided by git-hooks-nix.flakeModule:
      # - checks.${system}.pre-commit: runs all pre-commit hooks (treefmt, reuse, etc.)
      #
      # Developer workflow:
      # - nix/devshell.nix uses config.pre-commit.installationScript to install
      #   git hooks into .git/hooks/ when entering the dev environment
      # - The hooks run automatically on `git commit` for staged files only
      #
      # CI workflow:
      # - checks.${system}.pre-commit runs all hooks on all tracked files
      # - Used by .github/workflows/check.yml to enforce code standards

      checks = { };

      pre-commit = {
        settings = {
          hooks = {
            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
            };
            reuse = {
              enable = true;
              package = pkgs.reuse;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
            };
            end-of-file-fixer = {
              enable = true;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
              # Exclude files that should not be modified
              excludes = [
                ".*\\.patch$"
                ".*\\.dts$"
              ];
            };
            trim-trailing-whitespace = {
              enable = true;
              # Run on pre-commit to only check staged files
              stages = [ "pre-commit" ];
              # Excludes files that should not be modified
              excludes = [
                ".*\\.patch$"
                ".*\\.dts$"
              ];
            };
          };
        };
      };
    };
}
