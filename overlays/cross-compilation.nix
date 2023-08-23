# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
{...}: {
  nixpkgs.overlays = [
    # Overlay for element-desktop based on https://github.com/NixOS/nixpkgs/pull/241710
    (final: prev: {
      element-desktop =
        (prev.element-desktop.override {
          # Disable keytar, it breaks cross-build. Saving passwords would be not available.
          useKeytar = false;
        })
        .overrideAttrs (oldED: {
          seshat = oldED.seshat.overrideAttrs (oldSeshat: {
            buildPhase =
              builtins.replaceStrings
              # Add extra cargo options required for cross-compilation
              ["build --release"]
              ["build --release -- --target ${prev.rust.toRustTargetSpec prev.stdenv.hostPlatform} -Z unstable-options --out-dir target/release"]
              # Replace target 'fixup_yarn_lock' with build one
              (builtins.replaceStrings ["${prev.fixup_yarn_lock}"] ["${prev.buildPackages.fixup_yarn_lock}"] oldSeshat.buildPhase);
          });
        });
    })
    (final: prev: let
      crossCompiling = prev.stdenv.buildPlatform != prev.stdenv.hostPlatform;
      filterOutByName = name: builtins.filter (x: (builtins.baseNameOf x) != name);
      crossPatch = final.buildPackages.fetchpatch2 {
        url = "https://raw.githubusercontent.com/ck3d/nixpkgs/2d6f287f403f11f48bba19e2b2f2a7050592d51a/pkgs/development/interpreters/perl/cross.patch";
        sha256 = "sha256-ha7GPgSePU5P/UQpxnIEZD6CyJfDRUsfcysgBoVKrbc=";
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
      # TODO: Remove if this PR gets backported to nixos-23.05
      # https://github.com/NixOS/nixpkgs/pull/245228
      libjack2 = prev.libjack2.overrideAttrs (old: {
        prePatch = ''
        '';
        postPatch = ''
          patchShebangs --build svnversion_regenerate.sh
        '';
      });
    })
  ];
}
