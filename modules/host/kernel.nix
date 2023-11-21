# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  baseKernel =
    if hyp_cfg.enable
    then
      pkgs.linux_6_1.override {
        argsOverride = rec {
          src = pkgs.fetchurl {
            url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
            hash = "sha256-qH4kHsFdU0UsTv4hlxOjdp2IzENrW5jPbvsmLEr/FcA=";
          };
          version = "6.1.55";
          modDirVersion = "6.1.55";
        };
      }
    else pkgs.linux_latest;
  hardened_kernel = pkgs.linuxManualConfig rec {
    inherit (baseKernel) src modDirVersion kernelPatches;
    version = "${baseKernel.version}-ghaf-hardened";
    /*
    baseline "make tinyconfig"
    - enabled for 64-bit, TTY, printk and initrd
    - fixed following NixOS required assertions via "make menuconfig" + search
    (following is documented here to highlight NixOS required (asserted) kernel features)
    ❯ nix build .#packages.x86_64-linux.lenovo-x1-carbon-gen11-debug --accept-flake-config
    error:
       Failed assertions:
       - CONFIG_DEVTMPFS is not enabled!
       - CONFIG_CGROUPS is not enabled!
       - CONFIG_INOTIFY_USER is not enabled!
       - CONFIG_SIGNALFD is not enabled!
       - CONFIG_TIMERFD is not enabled!
       - CONFIG_EPOLL is not enabled!
       - CONFIG_NET is not enabled!
       - CONFIG_SYSFS is not enabled!
       - CONFIG_PROC_FS is not enabled!
       - CONFIG_FHANDLE is not enabled!
       - CONFIG_CRYPTO_USER_API_HASH is not enabled!
       - CONFIG_CRYPTO_HMAC is not enabled!
       - CONFIG_CRYPTO_SHA256 is not enabled!
       - CONFIG_DMIID is not enabled!
       - CONFIG_AUTOFS4_FS is not enabled!
       - CONFIG_TMPFS_POSIX_ACL is not enabled!
       - CONFIG_TMPFS_XATTR is not enabled!
       - CONFIG_SECCOMP is not enabled!
       - CONFIG_TMPFS is not yes!
       - CONFIG_BLK_DEV_INITRD is not yes!
       - CONFIG_EFI_STUB is not yes!
       - CONFIG_MODULES is not yes!
       - CONFIG_BINFMT_ELF is not yes!
       - CONFIG_UNIX is not enabled!
       - CONFIG_INOTIFY_USER is not yes!
       - CONFIG_NET is not yes!
    ...
    additional NixOS dependencies (fixed):
    > modprobe: FATAL: Module uas not found ...
    > modprobe: FATAL: Module nvme not found ...
    ... < many packages enabled as M,
          others allowMissing = true with overlay
          - see implementation below under cfg.enable
    - also see https://github.com/NixOS/nixpkgs/issues/109280
      for the context >
    */

    configfile = ./ghaf_host_hardened_baseline;
    allowImportFromDerivation = true;
  };

  pkvm_patch = lib.mkIf config.ghaf.hardware.x86_64.common.enable [
    {
      name = "pkvm-patch";
      patch = ../virtualization/pkvm/0001-pkvm-enable-pkvm-on-intel-x86-6.1-lts.patch;
      structuredExtraConfig = with lib.kernel; {
        KVM_INTEL = yes;
        KSM = no;
        PKVM_INTEL = yes;
        PKVM_INTEL_DEBUG = yes;
        PKVM_GUEST = yes;
        EARLY_PRINTK_USB_XDBC = yes;
        RETPOLINE = yes;
      };
    }
  ];

  kern_cfg = config.ghaf.host.kernel_hardening;
  hyp_cfg = config.ghaf.host.hypervisor_hardening;
in
  with lib; {
    options.ghaf.host.kernel_hardening = {
      enable = mkEnableOption "Host kernel hardening";
    };

    options.ghaf.host.hypervisor_hardening = {
      enable = mkEnableOption "Hypervisor hardening";
    };

    config = mkIf kern_cfg.enable {
      boot.kernelPackages = pkgs.linuxPackagesFor hardened_kernel;
      boot.kernelPatches = mkIf (hyp_cfg.enable && "${baseKernel.version}" == "6.1.55") pkvm_patch;
      # https://github.com/NixOS/nixpkgs/issues/109280#issuecomment-973636212
      nixpkgs.overlays = [
        (_final: prev: {
          makeModulesClosure = x:
            prev.makeModulesClosure (x // {allowMissing = true;});
        })
      ];
    };
  }
