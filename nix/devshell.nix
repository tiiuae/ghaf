# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{inputs, ...}: {
  imports = with inputs; [
    flake-root.flakeModule
    # TODO this import needs to be filtered to remove RISCV
    # pre-commit-hooks-nix.flakeModule
  ];
  perSystem = {pkgs, ...}:
  # TODO clean up
  # let
  #inherit (lib.flakes) platformPkgs;
  #in {
  {
    devShells.kernel = pkgs.mkShell {
      packages = with pkgs; [
        ncurses
        pkg-config
        python3
        python3Packages.pip
      ];

      inputsFrom = [pkgs.linux_latest];

      shellHook = ''
        export src=${pkgs.linux_latest.src}
        if [ ! -d "linux-${pkgs.linux_latest.version}" ]; then
          unpackPhase
          patchPhase
        fi
        cd linux-${pkgs.linux_latest.version}

        # python3+pip for kernel-hardening-checker
        export PIP_PREFIX=$(pwd)/_build/pip_packages
        export PYTHONPATH="$PIP_PREFIX/${pkgs.python3.sitePackages}:$PYTHONPATH"
        export PATH="$PIP_PREFIX/bin:$PATH"

        # install kernel-hardening-checker via pip under "linux-<version" for
        # easy clean-up with directory removal - if not already installed
        if [ ! -f "_build/pip_packages/bin/kernel-hardening-checker" ]; then
          python3 -m pip install git+https://github.com/a13xp0p0v/kernel-hardening-checker
        fi

        export PS1="[ghaf-kernel-devshell:\w]$ "
      '';
    };

    devShells.default = pkgs.mkShell {
      name = "Ghaf devshell";
      #TODO look at adding Mission control etc here
      packages = with pkgs; [
        git
        nix
        nixos-rebuild
        reuse
        alejandra
        mdbook
        #TODO enable cachix (filter out from RISCV)
        #cachix
      ];

      # TODO Add pre-commit.devShell (needs to exclude RiscV)
      # https://flake.parts/options/pre-commit-hooks-nix
    };
  };
}
