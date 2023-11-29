# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{inputs, ...}: {
  imports = with inputs; [
    flake-root.flakeModule
    # TODO this import needs to be filtered to remove RISCV
    # pre-commit-hooks-nix.flakeModule
  ];
  perSystem = {
    pkgs,
    inputs',
    lib,
    ...
  }: {
    devShells.kernel-x86 = pkgs.mkShell {
      name = "Kernel-x86 devshell";
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
          python3 -m pip --disable-pip-version-check \
            install git+https://github.com/a13xp0p0v/kernel-hardening-checker
        fi

        export PS1="[ghaf-kernel-devshell:\w]$ "
      '';
      # use "eval $checkPhase" - see https://discourse.nixos.org/t/nix-develop-and-checkphase/25707
      checkPhase = "cp ../modules/host/ghaf_host_hardened_baseline ./.config && make -j$(nproc)";

    };

    devShells.default = let
      nix-build-all = pkgs.writeShellApplication {
        name = "nix-build-all";
        runtimeInputs = let
          devour-flake = pkgs.callPackage inputs.devour-flake {};
        in [
          pkgs.nix
          devour-flake
        ];
        text = ''
          # Make sure that flake.lock is sync
          nix flake lock --no-update-lock-file

          # Do a full nix build (all outputs)
          devour-flake . "$@"
        '';
      };
    in
      pkgs.mkShell {
        name = "Ghaf devshell";
        #TODO look at adding Mission control etc here
        packages = with pkgs;
          [
            git
            nix
            nixos-rebuild
            reuse
            alejandra
            mdbook
            nix-build-all
            inputs'.nix-fast-build.packages.default
          ]
          ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") cachix;

        # TODO Add pre-commit.devShell (needs to exclude RiscV)
        # https://flake.parts/options/pre-commit-hooks-nix
      };
  };
}
