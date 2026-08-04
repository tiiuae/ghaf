# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# chromium does not cross-compile out of the box (aarch64-from-x86_64). Two
# independent breaks, both diagnosed and fixed against a real 96-core build:
#
#   1. The spliced buildPackages rust-bindgen wrapper is target-flavored: it
#      bakes `-nostdlibinc -idirafter <aarch64-glibc-dev>/include` into every
#      invocation, but chromium also runs bindgen for build-platform (host
#      toolchain) actions -- those then see only aarch64 libc headers and die
#      on aarch64 SVE types (`unknown type name '__SVFloat32_t'`). Patch
#      run_bindgen.py so invocations whose clang --target matches the build
#      platform get the build glibc via BINDGEN_EXTRA_CLANG_ARGS (-isystem
#      wins over the wrapper's -idirafter); target invocations are untouched.
#   2. dawn's pure-Go codegen host tool: the nixpkgs go attempts external
#      linking unconditionally, and with the cross derivation's CC pointing at
#      aarch64 clang the link feeds amd64 objects to the aarch64 linker.
#      CGO_ENABLED=0 alone does not stop the external link; force internal.
#
# Plumbing: the fixes live in the unwrapped browser derivation, which the
# chromium wrapper reaches only through an internal scope with no override
# hook. replaceDependencies needs import-from-derivation (disabled here), and
# replaceDirectDependencies rewrites *built* outputs, which would first build
# the broken original browser. Instead, rewrite the wrapper's buildCommand at
# eval time: swap the browser's output paths for the patched browser's and
# drop the original browser from the string context so it is never built.
# Everything else in the wrapper (and native builds) is untouched.
{ prev }:
let
  inherit (prev) lib stdenv;
  cross = stdenv.hostPlatform != stdenv.buildPlatform;

  oldBrowser = prev.chromium.browser;
  crossBrowser = oldBrowser.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      # Single-line replacement: an indented multi-line python block would be
      # mangled by nix indented-string whitespace stripping.
      + ''
        substituteInPlace build/rust/gni_impl/run_bindgen.py --replace-fail \
          "env = os.environ" \
          "env = os.environ; env.update({'BINDGEN_EXTRA_CLANG_ARGS': '-isystem ${lib.getDev prev.pkgsBuildBuild.stdenv.cc.libc}/include'} if any(a.startswith('--target=${stdenv.buildPlatform.parsed.cpu.name}') for a in genargs) else {})"
      '';
    preConfigure = (old.preConfigure or "") + ''
      export CGO_ENABLED=0
      export GOFLAGS=-ldflags=-linkmode=internal
    '';
  });
in
if cross then
  prev.chromium.overrideAttrs (old: {
    buildCommand =
      let
        plain = builtins.unsafeDiscardStringContext old.buildCommand;
        swapped =
          builtins.replaceStrings
            [
              (builtins.unsafeDiscardStringContext oldBrowser.outPath)
              (builtins.unsafeDiscardStringContext oldBrowser.sandbox.outPath)
            ]
            [
              crossBrowser.outPath
              crossBrowser.sandbox.outPath
            ]
            plain;
        # Re-attach the context of every other dependency the discard above
        # stripped (coreutils, xdg-utils, ...), minus the original browser.
        keptContext = removeAttrs (builtins.getContext old.buildCommand) [
          (builtins.unsafeDiscardStringContext oldBrowser.drvPath)
        ];
      in
      builtins.appendContext swapped keptContext;
  })
else
  prev.chromium
