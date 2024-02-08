# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{inputs, ...}: {
  perSystem = {
    pkgs,
    self',
    system,
    ...
  }: let
    mkKernelShell = {
      platform,
      linux,
      extraPackages ? [],
      shellHook ? "",
    }:
      pkgs.mkShell {
        name = "Kernel-${platform} devshell";
        packages = with pkgs;
          [
            ncurses
            pkg-config
            self'.packages.kernel-hardening-checker
          ]
          ++ extraPackages;

        inputsFrom = [linux];

        shellHook = ''
          export src=${linux.src}
          if [ -d "$src" ]; then
            # Jetpack's kernel named "source-patched" or likewise, workaround it
            linuxDir=$(stripHash ${linux.src})
          else
            linuxDir="linux-${linux.version}"
          fi
          if [ ! -d "$linuxDir" ]; then
            unpackPhase
            patchPhase
          fi
          cd "$linuxDir"
          # extra post-patching for NVidia
          ${shellHook}

          export PS1="[ghaf-kernel-${platform}-devshell:\w]$ "
        '';
        # use "eval $checkPhase" - see https://discourse.nixos.org/t/nix-develop-and-checkphase/25707
        checkPhase = "cp ../modules/host/ghaf_host_hardened_baseline-${platform} ./.config && make -j$(nproc)";
      };
  in {
    devShells.kernel-x86 = mkKernelShell {
      platform = "x86";
      linux = pkgs.linux_latest;
    };
    devShells.kernel-jetson-orin = mkKernelShell {
      platform = "jetson-orin";
      linux = inputs.jetpack-nixos.legacyPackages.${system}.kernel;
      extraPackages = [pkgs.gawk];
      shellHook = ''
        patchShebangs scripts/
      '';
    };
  };
}
