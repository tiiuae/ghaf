# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Cross build fix for jetpack-nixos' stuart-built UEFI firmware.
#
# stuart.nix adds gcc 16's -Wno-error flags to NIX_CFLAGS_COMPILE only, but
# EDK2 BaseTools is built with CC_FOR_BUILD, which reads the _FOR_BUILD flags
# when cross compiling. The firmware builders load stuart.nix through their callPackage argument,
# so wrap it to add the flags to every stuart derivation.
# TODO: drop once tiiuae/jetpack-nixos second-october-rebase sets
# NIX_CFLAGS_COMPILE_FOR_BUILD in pkgs/uefi-firmware/stuart.nix.
(final: prev: {
  nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
    _jfinal: jprev:
    let
      inherit (final.stdenv) buildPlatform hostPlatform;
      withBuildFlags =
        pkg:
        pkg.override {
          callPackage =
            fn: args:
            let
              mk = final.callPackage fn args;
            in
            # r39 forwards its arguments to stuart.nix, which reuses callPackage for pyenv.nix.
            if baseNameOf (toString fn) != "stuart.nix" then
              mk
            else
              drvArgs:
              (mk drvArgs).overrideAttrs (o: {
                env = o.env // {
                  NIX_CFLAGS_COMPILE_FOR_BUILD = "-Wno-error=discarded-qualifiers -Wno-error=unused-but-set-variable";
                };
              });
        };
    in
    prev.lib.optionalAttrs (buildPlatform != hostPlatform) {
      uefi-firmware = withBuildFlags jprev.uefi-firmware;
      jetsonStandaloneMMOptee = withBuildFlags jprev.jetsonStandaloneMMOptee;
    }
  );
})
