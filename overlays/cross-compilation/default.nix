# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
(final: prev: {
  # Fix for setuptools-rust cross-compilation hook mismatch.
  # When building Python packages natively (host == target), the setuptools-rust
  # hook was incorrectly setting PYO3_CROSS_LIB_DIR to pythonOnTargetForTarget
  # (which points to cross-compiled Python) while CARGO_BUILD_TARGET was set to
  # the native platform. This caused PyO3 to fail finding sysconfigdata.
  # This fix backports https://github.com/NixOS/nixpkgs/pull/480005
  # which adds a condition to skip the setup hook when host == target.
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_python-final: python-prev: {
      setuptools-rust =
        if final.lib.systems.equals final.stdenv.hostPlatform final.stdenv.targetPlatform then
          # When host == target (native build), remove the setup hook entirely
          # to avoid the cross-compilation environment variables being set incorrectly
          python-prev.setuptools-rust.overrideAttrs (oldAttrs: {
            postFixup = (oldAttrs.postFixup or "") + ''
              # Remove the problematic cross-compilation setup hook for native builds
              rm -f $out/nix-support/setup-hook
            '';
          })
        else
          python-prev.setuptools-rust;
    })
  ];
})
