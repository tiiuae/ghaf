# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.ghaf.host.kernel.hardening;

  kernelDrv = pkgs.callPackage ./packages/linux-pkvm-jetson {
    argsOverride.defconfig = "debug_defconfig";

    structuredExtraConfig = with lib.kernel; {
      VIRTIO_FS = module;
      TCG_TIS = module;
      RTW89 = module;
      RTW89_8852CE = module;
      # PCIe device assignment
      PKVM_GUEST_SELF_ASSIGN_DEVICE = yes;

      TEGRA_BPMP = yes;
      TEGRA_BPMP_HOST_PROXY = yes;
      TEGRA_BPMP_PKVM = yes;
    };
  };

  assignableDevicesOverlay = ''
    /dts-v1/;
    /plugin/;

    / {
        overlay-name = "pKVM device assignment";
        compatible = "nvidia,tegra234";

        fragment@0 {
            target-path = "/";
            __overlay__ {
                pkvm_devices {
                    compatible = "pkvm,device-assignment";
                    devices = <${
                      lib.concatImapStringsSep " " (pos: d: "&${d} ${toString (pos - 1)}") cfg.allowedPassthroughDevices
                    }>;
                };

                pkvm_devices_ac {
                    compatible = "pkvm,device-auditing";

                    bpmp {
                        compatible = "pkvm,mediated-device";
                        memory-pools = <&cpu_bpmp_tx &cpu_bpmp_rx>;
                        pkvm,driver = "bpmp_hyp";
                    };
                };
            };
        };
    };
  '';
in
{
  _file = ./orin-pkvm-host.nix;

  config = lib.mkIf cfg.hypervisor.enable {
    nixpkgs.overlays = [
      self.overlays.jetpack7-nvidia-oot
    ];

    boot.kernelPackages = lib.mkForce (
      (pkgs.linuxPackagesFor kernelDrv).extend pkgs.nvidia-jetpack.kernelPackagesOverlay
    );

    # Use latest Jetpack for better compatibility between Linux 6.18 and Jetson oot modules
    hardware.nvidia-jetpack.majorVersion = "7";

    # Signal that the active kernel is not the bsp-default
    ghaf.hardware.nvidia.orin.kernelVersion = lib.mkForce "6-18-jetson-pkvm";

    hardware.deviceTree.enable = true;
    hardware.deviceTree.overlays = lib.mkAfter [
      {
        name = "pkvm_devices_overlay";
        dtsText = assignableDevicesOverlay;
        # The overlay tries to apply to every dt in dt source dir, including other
        # SoCs / carrier boards that may not have the referenced labels.
        filter = config.hardware.deviceTree.name;
      }
    ];

    boot.kernelParams = [
      "pkvm.assign_permissive=1"
      "kvm-arm.hyp_iommu_pages=86016" # 0x15000
    ];

    # The Realtek nvidia-oot driver is disabled and replaced by the mainline driver
    boot.initrd.availableKernelModules.rtl8852ce = lib.mkForce false;

    # BPMP drivers are already included in the Jetson pKVM kernel
    ghaf.hardware.nvidia.virtualization.enable = lib.mkForce false;

    # Enable unified gui-vm instead of split display/compute VMs
    ghaf.hardware.nvidia.passthroughs.gui_vm.enable = true;
    ghaf.hardware.nvidia.passthroughs.gpu_vm.enable = lib.mkForce false;
    ghaf.hardware.nvidia.passthroughs.disp_vm.enable = lib.mkForce false;
    # DCE proxy is not needed in the absence of decoupled display
    ghaf.hardware.nvidia.virtualization.host.dce.enable = lib.mkForce false;

    # Disable wait for plymouth since display is disabled
    ghaf.graphics.boot.enable = false;
  };
}
