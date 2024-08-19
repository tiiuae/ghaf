# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
#
# TODO: This is not a package but a module
{
  config,
  pkgs,
  lib,
}:
{
  kernelPatches ? [ ],
  config_baseline,
  host_build ? false,
}:
let
  kernel_package = pkgs.linux_latest;
  version = "${kernel_package.version}-ghaf-hardened";
  modDirVersion = version;
  base_kernel = pkgs.linuxManualConfig rec {
    inherit (kernel_package) src;
    inherit version modDirVersion kernelPatches;
    /*
      NixOS required (asserted) kernel features
      to comply with no import from derivation.
      For the actual kernel build these config
      options must come via the kernel
      config_baseline argument
    */
    config = {
      CONFIG_DEVTMPFS = "y";
      CONFIG_CGROUPS = "y";
      CONFIG_INOTIFY_USER = "y";
      CONFIG_SIGNALFD = "y";
      CONFIG_TIMERFD = "y";
      CONFIG_EPOLL = "y";
      CONFIG_NET = "y";
      CONFIG_SYSFS = "y";
      CONFIG_PROC_FS = "y";
      CONFIG_FHANDLE = "y";
      CONFIG_CRYPTO_USER_API_HASH = "y";
      CONFIG_CRYPTO_HMAC = "y";
      CONFIG_CRYPTO_SHA256 = "y";
      CONFIG_DMIID = "y";
      CONFIG_AUTOFS_FS = "y";
      CONFIG_TMPFS_POSIX_ACL = "y";
      CONFIG_TMPFS_XATTR = "y";
      CONFIG_SECCOMP = "y";
      CONFIG_TMPFS = "y";
      CONFIG_BLK_DEV_INITRD = "y";
      CONFIG_EFI_STUB = "y";
      CONFIG_MODULES = "y";
      CONFIG_BINFMT_ELF = "y";
      CONFIG_UNIX = "y";
    };
    configfile = config_baseline;
  };

  generic_host_configs = ../../modules/hardware/x86_64-generic/kernel/host/configs;
  generic_guest_configs = ../../modules/hardware/x86_64-generic/kernel/guest/configs;
  # TODO: refactor - do we yet have any X1 specific host kernel configuration options?
  # - we could add a configuration fragment for host debug via usb-ethernet-adapter(s)

  kernel_features =
    lib.optionals config.ghaf.host.kernel.hardening.virtualization.enable [
      "${generic_host_configs}/virtualization.config"
    ]
    ++ lib.optionals config.ghaf.host.kernel.hardening.networking.enable [
      "${generic_host_configs}/networking.config"
    ]
    ++ lib.optionals config.ghaf.host.kernel.hardening.usb.enable [
      "${generic_host_configs}/usb.config"
    ]
    ++ lib.optionals config.ghaf.host.kernel.hardening.inputdevices.enable [
      "${generic_host_configs}/user-input-devices.config"
    ]
    ++ lib.optionals config.ghaf.host.kernel.hardening.debug.enable [
      "${generic_host_configs}/debug.config"
    ]
    ++ lib.optionals (config.ghaf.guest.kernel.hardening.enable && !host_build) [
      "${generic_guest_configs}/guest.config"
    ]
    ++ lib.optionals (config.ghaf.guest.kernel.hardening.graphics.enable && !host_build) [
      "${generic_guest_configs}/display-gpu.config"
    ];

  kernel =
    if lib.length kernel_features > 0 then
      base_kernel.overrideAttrs (_old: {
        inherit kernel_features;
        postConfigure = ''
          ./scripts/kconfig/merge_config.sh  -O $buildRoot $buildRoot/.config  $kernel_features;
        '';
      })
    else
      base_kernel;
in
kernel
