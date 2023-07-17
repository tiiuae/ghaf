# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
{...}: {
  nixpkgs.overlays = [
    (final: prev: let
      crossCompiling = prev.stdenv.buildPlatform != prev.stdenv.hostPlatform;
      filterOutByName = name: builtins.filter (x: (builtins.baseNameOf x) != name);
      # FIXME: should be prev.buildPackages.fetchpatch2, why I can't use fetchpatch2 here
      crossPatch = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/ck3d/nixpkgs/2d6f287f403f11f48bba19e2b2f2a7050592d51a/pkgs/development/interpreters/perl/cross.patch";
        sha256 = "06n6p078m9g12m82z6dz0h0qlkm394af7b21vhwdpjrr6kbjbvf2";
      };
      # function to list patches for debug purposes
      tracePatches = xs: map (x: builtins.trace (builtins.toString x) x) xs;
      # Attempt to port https://github.com/NixOS/nixpkgs/pull/225640/files to stable branch via overlay
      # Also included into https://github.com/NixOS/nixpkgs/pull/241848 (Remove it in next 23.11 stable, if this PR merged)
    in rec {
      perl536 = prev.perl536.overrideAttrs (old: {
        patches = (filterOutByName "MakeMaker-cross.patch" old.patches) ++ prev.lib.optional crossCompiling crossPatch;
      });
      perl536Packages = prev.perl536Packages.overrideScope (self: super: {
        perl = perl536; # Otherwise ModuleBuild builds with unpatched perl
        ModuleBuild = super.ModuleBuild.overrideAttrs (old: {
          postConfigure = prev.lib.optionalString crossCompiling ''
            # for unknown reason, the first run of Build fails
            ./Build || true
          '';
          postPatch = prev.lib.optionalString crossCompiling ''
            # remove version check since miniperl uses a stub of File::Temp, which do not provide a version:
            # https://github.com/arsv/perl-cross/blob/master/cnf/stub/File/Temp.pm
            sed -i '/File::Temp/d' \
              Build.PL

            # fix discover perl function, it can not handle a wrapped perl
            sed -i "s,\$self->_discover_perl_interpreter,'$(type -p perl)',g" \
              lib/Module/Build/Base.pm
          '';
        });
      });
    })
  ];
}
