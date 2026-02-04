# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  pkvmKernel = pkgs.linux_6_1.override {
    argsOverride = rec {
      src = pkgs.fetchurl {
        url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
        hash = "sha256-qH4kHsFdU0UsTv4hlxOjdp2IzENrW5jPbvsmLEr/FcA=";
      };
      version = "6.1.55";
      modDirVersion = version;
    };
  };

  pkvm_patch = [
    {
      name = "pkvm-patch";
      patch = ./0001-pkvm-enable-pkvm-on-intel-x86-6.1-lts.patch;
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

  hyp_cfg = config.ghaf.host.kernel.hardening.hypervisor;
in
{
  _file = ./default.nix;

  options.ghaf.host.kernel.hardening.hypervisor.enable = lib.mkOption {
    description = "Enable Hypervisor hardening feature";
    type = lib.types.bool;
    default = false;
  };
  config = lib.mkIf hyp_cfg.enable {
    boot.kernelPackages = pkgs.linuxPackagesFor pkvmKernel;
    boot.kernelPatches = pkvm_patch;
  };
}
