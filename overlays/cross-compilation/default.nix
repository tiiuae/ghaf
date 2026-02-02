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

  # Fix for sbsigntool cross-compilation.
  # Multiple issues need to be addressed:
  # 1. The create-ccan-tree script uses getopt which is not available in nativeBuildInputs.
  # 2. The configure script uses `uname -m` to detect EFI_ARCH, which returns the build
  #    machine architecture instead of the target architecture during cross-compilation.
  # 3. The lib/ccan Makefile uses hardcoded `ar` instead of the autoconf-detected AR.
  # This fix adds util-linux for getopt, patches configure.ac to use the correct
  # target architecture, and sets AR/RANLIB for make.
  sbsigntool = prev.sbsigntool.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
      final.buildPackages.util-linux
    ];
    makeFlags = (oldAttrs.makeFlags or [ ]) ++ [
      "AR=${final.stdenv.cc.targetPrefix}ar"
      "RANLIB=${final.stdenv.cc.targetPrefix}ranlib"
    ];
    configurePhase = ''
      runHook preConfigure

      substituteInPlace configure.ac --replace-warn "@@NIX_GNUEFI@@" "${final.gnu-efi}"

      # Fix EFI_ARCH to use target architecture instead of build machine's uname -m
      substituteInPlace configure.ac \
        --replace-warn 'EFI_ARCH=$(uname -m | sed' 'EFI_ARCH=$(echo ${final.stdenv.hostPlatform.parsed.cpu.name} | sed'

      lib/ccan.git/tools/create-ccan-tree --build-type=automake lib/ccan "talloc read_write_all build_assert array_size endian"
      touch AUTHORS
      touch ChangeLog

      echo "SUBDIRS = lib/ccan src docs" >> Makefile.am

      aclocal
      autoheader
      autoconf
      automake --add-missing -Wno-portability

      ./configure --prefix=$out

      runHook postConfigure
    '';
  });

  # Fix for efitools cross-compilation.
  # The Make.rules uses `uname -m` to detect ARCH, which returns the build machine
  # architecture instead of the target architecture during cross-compilation.
  # This causes x86_64-specific compiler flags (like -mno-red-zone) to be used
  # when building for aarch64, and wrong include paths to be used.
  # Also, the Makefile uses hardcoded `ar`, `nm`, and `objcopy` instead of the
  # cross-toolchain versions.
  # Additionally, openssl is needed at build time for certificate generation.
  efitools = prev.efitools.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [
      final.buildPackages.openssl
      final.buildPackages.sbsigntool
    ];
    postPatch = (oldAttrs.postPatch or "") + ''
      # Fix ar to use $(AR) variable
      substituteInPlace Make.rules --replace-warn 'ar rcv' '$(AR) rcv'
      # Fix nm to use $(NM) variable
      substituteInPlace Make.rules --replace-warn 'nm -D' '$(NM) -D'
      # Fix objcopy to use the cross-toolchain version
      substituteInPlace Make.rules --replace-warn 'OBJCOPY		= objcopy' 'OBJCOPY		= ${final.stdenv.cc.targetPrefix}objcopy'
    '';
    makeFlags = (oldAttrs.makeFlags or [ ]) ++ [
      "ARCH=${final.stdenv.hostPlatform.parsed.cpu.name}"
      "AR=${final.stdenv.cc.targetPrefix}ar"
      "NM=${final.stdenv.cc.targetPrefix}nm"
    ];
  });
})
