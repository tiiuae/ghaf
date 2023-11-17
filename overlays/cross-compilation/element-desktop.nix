# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
# Overlay for element-desktop based on https://github.com/NixOS/nixpkgs/pull/241710
(_final: prev: {
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
