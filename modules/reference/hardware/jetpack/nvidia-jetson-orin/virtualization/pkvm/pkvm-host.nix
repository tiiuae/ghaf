# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;

  nvidiaJetpackFixes = _final: prev: {
    # Fix CUDA compile failures for x86_64 cross-compile build
    config =
      prev.config
      // lib.optionalAttrs (prev.stdenv.hostPlatform.system != "aarch64-linux") {
        cudaCapabilities = [ ];
      };

    nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
      _sfinal: sprev: {
        # Fix build error with python 3.14:
        #   importlib.metadata.PackageNotFoundError: No package metadata was found for uefi-firmware-parser
        # Set dontCheckPythonMetadata to skip the pythonMetadataCheckPhase.
        # The nested overrides are needed to reach inside the uefi-firmware-parser derivation.
        patchfv = sprev.patchfv.override (prevArgs: {
          python3Packages = prevArgs.python3Packages // {
            buildPythonPackage =
              args: prevArgs.python3Packages.buildPythonPackage (args // { dontCheckPythonMetadata = true; });
          };
        });
      }
    );
  };

  jetpackHostKconfig =
    with lib.kernel;
    {
      # Needed for booting from USB.
      USB_UAS = module;
      VIDEOBUF2_DMA_CONTIG = yes;
      TCG_TIS = module;
      RTW89 = module;
      RTW89_8852CE = module;
    }
    // import "${inputs.jetpack-nixos-r39}/pkgs/kernels/common-arch.nix" { inherit lib; };

  ootExtraMakeFlags = [
    "kernel_name=pkvm"
    "NV_OOT_REALTEK_RTL8822CE_SKIP_BUILD=y"
    "NV_OOT_REALTEK_RTL8852CE_SKIP_BUILD=y"
  ];
  ootMakeFlagsToRemove = [
    "kernel_name=noble"
  ];

  jetpackKernelOverlay = final: prev: {
    nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
      _sfinal: sprev: {
        kernel = final.linux_6_18_jetson_pkvm.override {
          argsOverride.defconfig = "debug_defconfig";
          structuredExtraConfig = jetpackHostKconfig;
        };

        kernelPackagesOverlay =
          kfinal: kprev:
          let
            base = sprev.kernelPackagesOverlay kfinal kprev;
            inherit (kfinal) kernel;
          in
          base
          // lib.optionalAttrs (base ? nvidia-oot-modules) {
            nvidia-oot-modules = base.nvidia-oot-modules.overrideAttrs (oldAttrs: {
              nativeBuildInputs =
                oldAttrs.nativeBuildInputs
                ++ lib.optional (
                  !lib.any (d: (d.pname or null) == "bc") oldAttrs.nativeBuildInputs
                ) final.buildPackages.bc;

              makeFlags =
                kernel.commonMakeFlags
                ++ lib.subtractLists (
                  kernel.makeFlags ++ ootMakeFlagsToRemove ++ ootExtraMakeFlags
                ) oldAttrs.makeFlags
                ++ ootExtraMakeFlags;

              postPatch = (oldAttrs.postPatch or "") + ''
                if ! grep -q rtk_set_quirk nvidia-oot/drivers/bluetooth/realtek/rtk_bt.h; then
                  patch -p1 -d nvidia-oot < ${./0002-rtk_btusb-Fix-for-kernel-6.16.patch}
                fi
              '';
            });
          };
      }
    );
  };
in
{
  _file = ./pkvm-host.nix;

  config = lib.mkIf (cfg.kernelVersion == "stable-6-18-pkvm") {
    nixpkgs.overlays = [
      nvidiaJetpackFixes
      jetpackKernelOverlay
    ];

    hardware.nvidia-jetpack.majorVersion = lib.mkForce "7";

    # compilation of this nvidia-oot module was skipped
    boot.initrd.availableKernelModules.rtl8852ce = lib.mkForce false;

    # TEMP: ftpmSimTooling patch is missing from upstream jetpack-nixos
    # Disable until rebase
    ghaf.hardware.nvidia.orin.runtimeEkProvision.enable = false;

    # Passthroughs aren't ported yet
    ghaf.hardware.nvidia.virtualization.enable = lib.mkForce false;
    ghaf.hardware.nvidia.virtualization.host.dce.enable = lib.mkForce false;

    ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable = lib.mkForce false;
    ghaf.hardware.nvidia.passthroughs.gpu_vm.enable = lib.mkForce false;
    ghaf.hardware.nvidia.passthroughs.disp_vm.enable = lib.mkForce false;

    ghaf.hardware.nvidia.orin.agx.enableNetvmWlanPCIPassthrough = lib.mkForce false;
  };
}
