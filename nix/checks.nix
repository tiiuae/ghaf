# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  imports = [ inputs.git-hooks-nix.flakeModule ];
  perSystem =
    {
      config,
      lib,
      pkgs,
      self',
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
      # - Used by .github/workflows/check.yaml to enforce code standards

      # pkgs-by-name-for-flake-parts tracks upstream main. It has changed the shape of
      # legacyPackages twice Fail the bump here rather than at the first
      # missing package.
      checks.pkgs-by-name-shape =
        let
          # builtins.attrNames and builtins.readDir both return sorted names,
          # so these two lists are directly comparable.
          expected = lib.attrNames (
            lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../packages/pkgs-by-name)
          );
          found = lib.attrNames self'.legacyPackages;
          nonDerivations = lib.attrNames (
            lib.filterAttrs (_: value: !lib.isDerivation value) self'.legacyPackages
          );
          problems =
            lib.optional (found != expected) ''
              legacyPackages does not match packages/pkgs-by-name/:
                missing: ${toString (lib.subtractLists found expected)}
                extra:   ${toString (lib.subtractLists expected found)}
            ''
            ++ lib.optional (nonDerivations != [ ]) ''
              legacyPackages contains non-derivations: ${toString nonDerivations}
            '';
        in
        lib.throwIf (problems != [ ]) (lib.concatStringsSep "\n" problems) pkgs.emptyFile;

      # The machine table is a list of names, not a place to configure a machine.
      # Anything more than the declared fields belongs in a hardware module or a
      # reference profile.
      checks.laptop-table-is-data =
        let
          banned = [
            "ghaf."
            "lib."
            "import"
            "mkIf"
            "mkForce"
            "mkDefault"
          ];
          # Comments legitimately mention the banned words.
          code = map (l: lib.head (lib.splitString "#" l)) (
            lib.splitString "\n" (builtins.readFile ../targets/laptop/machines.nix)
          );
          hits = lib.concatMap (l: map (b: "  ${b}  in:${l}") (lib.filter (b: lib.hasInfix b l) banned)) code;
        in
        lib.throwIf (hits != [ ]) ''
          targets/laptop/machines.nix must be data only. Found:
          ${lib.concatStringsSep "\n" hits}
        '' pkgs.emptyFile;

      pre-commit = {
        settings = {
          hooks = {
            convco = {
              # Disable to ease dev workflow, conventional commits are enforced via GitHub actions
              enable = false;
              # Add bump type
              settings.configPath = pkgs.writeText "convco.yaml" ''
                types:
                  - type: bump
                    increment: None
                    section: Other
                    hidden: true
              '';
            };
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
