# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#  Configuration for NVIDIA Jetson Orin AGX/NX
#
{
  lib,
  self,
  inputs,
  ...
}:
let
  inherit (inputs) jetpack-nixos nixpkgs;
  system = "aarch64-linux";
  pkgsX86 = nixpkgs.legacyPackages.x86_64-linux;
  lazyPackage =
    name: drv:
    (lib.lazyDerivation {
      derivation = drv;
    })
    // {
      inherit name;
    };

  # Unified Ghaf configuration builder
  ghaf-configuration = self.builders.mkGhafConfiguration {
    inherit self inputs;
    inherit (self) lib;
  };

  # Orin-specific modules (UEFI patches, OP-TEE, format modules)
  orinSpecificModules = [
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/format-module.nix
    jetpack-nixos.nixosModules.default
  ];

  # Crosvm and ghaf-device-manager are the default virtualization stack for
  # every exported Orin target and all generated variants.
  orinCrosvmModule = {
    ghaf.hardware.nvidia.orin.crosvm.enable = true;
    ghaf.hardware.nvidia.passthroughs.gui_vm.enable = true;
  };

  # Common modules shared across all Orin configurations
  commonModules = orinSpecificModules ++ [
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-profiles-orin
    self.nixosModules.profiles
    orinCrosvmModule
  ];

  linuxPkvmPackages =
    pkgs:
    pkgs.linuxPackagesFor (
      pkgs.linux_7_1.override {
        argsOverride = rec {
          src = inputs.linux-pkvm;
          version = "7.1.7";
          modDirVersion = version;
        };
      }
    );

  linux71PkvmGuestSupportModule =
    { lib, ... }:
    {
      boot.kernelPatches = [
        {
          name = "Arm pKVM guest support";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            DMA_RESTRICTED_POOL = yes;
            ARM_PKVM_GUEST = yes;
          };
        }
      ];
    };

  linux71PkvmGuestModule =
    { lib, pkgs, ... }:
    {
      imports = [ linux71PkvmGuestSupportModule ];
      boot.kernelPackages = lib.mkForce pkgs.linuxPackages_7_1;
    };

  linux71ExternalPkvmGuestModule =
    { lib, pkgs, ... }:
    {
      imports = [ linux71PkvmGuestSupportModule ];
      # This module extends guests inherited from the rollback target, whose
      # ordinary Linux 7.1 selection is already forced.
      boot.kernelPackages = lib.mkOverride 40 (linuxPkvmPackages pkgs);
      boot.kernelPatches = [
        {
          name = "Disable protected device assignment by default";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            PKVM_PVIOMMU = lib.mkDefault no;
            VFIO_PKVM_IOMMU = no;
          };
        }
      ];
    };

  linux71PkvmAssignedGuestModule =
    { lib, ... }:
    {
      boot.kernelPatches = [
        {
          name = "Arm pKVM protected device assignment";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            PKVM_PVIOMMU = yes;
          };
        }
      ];
    };

  netvmCrosvmVgicItsModule =
    { config, lib, ... }:
    {
      assertions = [
        {
          assertion = config.microvm.hypervisor == "crosvm";
          message = "The AGX NetVM vGIC ITS canary requires Crosvm";
        }
      ];

      # AArch64 Crosvm leaves the virtual ITS disabled by default, which makes
      # PCI passthrough fall back to legacy INTx. Expose the ITS so the
      # physical WLAN device can use MSI inside NetVM.
      microvm.crosvm.extraArgs = lib.mkIf (config.microvm.hypervisor == "crosvm") [
        "--irqchip"
        "kernel[allow-vgic-its]"
      ];
    };

  protectedVmWithoutFirmwareModule =
    { config, lib, ... }:
    {
      assertions = [
        {
          assertion = config.microvm.hypervisor == "crosvm";
          message = "The AGX protected VM canary requires Crosvm";
        }
      ];

      # Start with direct kernel boot so guest-memory isolation can be tested
      # independently of pVM firmware and secret provisioning.
      microvm.crosvm.protection.mode = lib.mkIf (
        config.microvm.hypervisor == "crosvm"
      ) "protected-without-firmware";

      # A vhost-user backend maps guest memory into a separate host process.
      # With upstream pKVM, an access outside the guest-shared restricted DMA
      # pool force-reclaims and poisons the private page. Keep this first
      # protected guest free of virtio-fs; its Nix store is supplied by the
      # target's block-backed store image instead.
      microvm.shares = lib.mkForce [ ];

      # Upstream Linux reports protected-VM support by accepting the protected
      # KVM_CREATE_VM type. Crosvm otherwise probes an Android-only capability
      # number after the VM has already been created and rejects Linux 7.1.
      microvm.crosvm.package = lib.mkForce (
        config.microvm.vmHostPackages.crosvm.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./patches/crosvm-upstream-pkvm-create-vm.patch ];
        })
      );
    };

  linux71PkvmHostModule =
    { lib, pkgs, ... }:
    {
      # jetpack-nixos owns the NVIDIA host compatibility layer. Select Linux
      # 7.1 only for this AGX debug target while retaining its 6.6 default for
      # every other Orin export.
      hardware.nvidia-jetpack.virtualization.dceHost.kernelPackages = lib.mkForce pkgs.linuxPackages_7_1;

      # MGBE0 owns NetVM's kernel selection so its BPMP integration follows
      # the selected package set. GUIVM retains its independent 6.12 default.
      ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.guestKernelPackages =
        lib.mkForce pkgs.linuxPackages_7_1;

      # Linux 7.1's defconfig makes the eMMC block layer modular. Preserve the
      # upstream Tegra boot closure without requesting unavailable NVIDIA OOT
      # modules such as nvethernet and nvpps.
      boot.initrd.availableKernelModules = lib.mkForce [
        "autofs"
        "efivarfs"
        "ext2"
        "ext4"
        "xhci-tegra"
        "ucsi_ccg"
        "typec_ucsi"
        "typec"
        "nvme"
        "mmc_block"
        "phy-tegra-xusb"
        "i2c-tegra"
        "phy_tegra194_p2u"
        "pcie_tegra194"
      ];
    };

  pkvmDebugModule =
    { lib, pkgs, ... }:
    {
      # The rollback target keeps pristine Linux stable. Only this derived
      # target consumes the validated pKVM integration source.
      hardware.nvidia-jetpack.virtualization.dceHost = {
        # Retain the validated host DCE compatibility closure even though this
        # reduced target has no GUI consumer.
        enable = lib.mkForce true;
        kernelPackages = lib.mkOverride 40 (linuxPkvmPackages pkgs);
      };
      ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.guestKernelPackages = lib.mkOverride 40 (
        linuxPkvmPackages pkgs
      );

      # Keep pKVM development in one evolving debug target. The
      # ordinary accelerated GUI target remains the rollback image.
      boot.kernelParams = [
        "kvm-arm.mode=protected"
        # Keep protected identity-DMA allocations below SDMMC's 34-bit limit.
        "mem=12G"
        # The validated firmware state-save path is protected nVHE.
        "arm64_sw.hvhe=0"
        "id_aa64mmfr1.vh=0"
      ];

      boot.blacklistedKernelModules = [
        # The DSU PMU callback accesses a register trapped by protected EL2.
        "arm_dsu_pmu"
        # GUIVM is absent, so its high-IOVA display anchor has no consumer.
        "dce-iso-anchor"
        # Protected PCI assignment requires a separate reset backend.
        "rtw88_8822ce"
      ];

      # Keep host-IOMMU debug iterations small. GUIVM and FlatpakVM do not
      # participate in this service-plane checkpoint, and carrying their
      # closures makes every destructive flash substantially larger. ChromiumVM
      # is the one protected application endpoint included after AdminVM,
      # NetVM, virtual networking, and GIVC passed together. This remains
      # confined to the pKVM debug target; the accelerated GUI target is the
      # full-topology rollback.
      ghaf.hardware.nvidia.passthroughs.gui_vm.enable = lib.mkForce false;
      ghaf.virtualization.microvm.guivm.enable = lib.mkForce false;
      ghaf.virtualization.microvm.appvm.enable = lib.mkForce true;
      ghaf.reference.appvms.enable = lib.mkForce true;
      ghaf.reference.appvms.chromium.enable = lib.mkForce true;
      ghaf.reference.appvms.flatpak.enable = lib.mkForce false;

      # Kernel code comes from linux-pkvm; Ghaf retains target configuration.
      boot.kernelPatches = [
        {
          name = "Tegra pKVM protected-device configuration";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            ARM_SMMU = no;
            ARM_SMMU_TEGRA_PKVM = yes;
            IOMMU_POOL_PAGES = freeform "0x10000";
            PKVM_PVIOMMU = yes;
            VFIO_PKVM_IOMMU = yes;
          };
        }
      ];

      hardware.deviceTree = {
        enable = true;
        overlays = [
          {
            name = "mgbe0-protected-assignment";
            dtsFile = ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/pkvm/mgbe0-protected-assignment-overlay.dts;
          }
        ];
      };

      ghaf.hardware.nvidia.orin.agx.enableNetvmWlanPCIPassthrough = lib.mkForce false;
      ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.crosvmIommu = "pkvm-iommu";

      # Preserve the nVHE timer, virtualization, and interrupt-control state
      # across NVIDIA R36.5 TF-A CPU power-down.
      nixpkgs.overlays = [
        (_final: prev: {
          nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
            _finalJetpack: prevJetpack: {
              gitRepos = prevJetpack.gitRepos // {
                "tegra/optee-src/atf" = prev.applyPatches {
                  name = "atf-pkvm";
                  src = prevJetpack.gitRepos."tegra/optee-src/atf";
                  patches = [
                    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/pkvm/0001-tegra-t234-save-and-restore-virtualization-registers.patch
                  ];
                };
              };
            }
          );
        })
      ];

      # Ghaf's boot-order module starts every configured VM regardless of the
      # microvm.nix autostart setting. Disable it so the reduced target can use
      # explicit weak ordering between its three protected VMs.
      ghaf.microvm-boot.enable = lib.mkForce false;
      # balloon-manager is normally pulled into microvms.target and requires
      # each ballooned AppVM's memory manager, which in turn requires the VM.
      # Remove that indirect startup path for this staged target.
      systemd.services.balloon-manager.wantedBy = lib.mkForce [ ];

      # Protected guests cannot use the normal vhost-user ro-store without
      # risking host access to private guest pages. Use the established Ghaf
      # EROFS store-disk path for every guest in this debug target.
      ghaf.virtualization.microvm.storeOnDisk.enable = true;

      # AdminVM is the device-free GIVC control-plane guest.
      ghaf.virtualization.vmConfig.sysvms.adminvm.extraModules = [
        linux71ExternalPkvmGuestModule
        protectedVmWithoutFirmwareModule
      ];
      ghaf.virtualization.vmConfig.sysvms.netvm.extraModules = [
        linux71ExternalPkvmGuestModule
        linux71PkvmAssignedGuestModule
        protectedVmWithoutFirmwareModule
        {
          microvm.crosvm.protection.allowDeviceAssignment = true;
        }
      ];
      ghaf.virtualization.vmConfig.appvms.chromium = {
        # Keep ChromiumVM's declared 6 GiB as its complete allocation. pKVM
        # does not support Ghaf's balloon lifecycle yet, and the default ratio
        # would otherwise reserve 18 GiB.
        balloonRatio = 0;
        extraModules = [
          linux71ExternalPkvmGuestModule
          protectedVmWithoutFirmwareModule
          {
            # XDG item exchange uses virtio-fs. A protected guest must not use
            # that host-visible vhost-user memory backend.
            ghaf.xdgitems.enable = lib.mkForce false;
          }
        ];
      };
      # EL2 must reset MGBE0 before assigning it to a protected guest and
      # again while reclaiming it. Keep the BPMP clock votes alive across the
      # complete assignment lifetime; touching the powered-down MAC from nVHE
      # can raise an external abort instead of returning a reset error.
      systemd.services.pkvm-mgbe0-clocks = {
        description = "Keep MGBE0 clocks enabled for protected assignment";
        wantedBy = [ "multi-user.target" ];
        before = [ "microvm@net-vm.service" ];
        after = [ "sys-kernel-debug.mount" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for clock in /sys/kernel/debug/bpmp/debug/clk/mgbe0_*; do
            echo 1 > "$clock/state"
          done
        '';
      };
      systemd.services."microvm@net-vm" = {
        requires = [ "pkvm-mgbe0-clocks.service" ];
        # AdminVM owns the GIVC control plane. Start it first so NetVM's agent
        # can register as soon as its internal TAP becomes routable, but keep
        # NetVM available for recovery if the control plane itself fails.
        wants = [ "microvm@admin-vm.service" ];
        after = [
          "microvm@admin-vm.service"
          "pkvm-mgbe0-clocks.service"
        ];
      };
      systemd.services."microvm@chromium-vm" = {
        # ChromiumVM consumes both the routed network and the GIVC control
        # plane. Keep these dependencies weak so a failed service-plane VM is
        # visible as a degraded boot rather than suppressing the app canary.
        wants = [
          "microvm@admin-vm.service"
          "microvm@net-vm.service"
        ];
        after = [
          "microvm@admin-vm.service"
          "microvm@net-vm.service"
        ];
      };

      # MGBE0 assignment, protected teardown, TAP networking, AF_VSOCK, and
      # GIVC registration pass together. Autostart the three selected protected
      # VMs while the broad boot orchestrator stays disabled, so GUIVM and
      # FlatpakVM remain out of this image.
      microvm.vms = {
        "admin-vm".autostart = lib.mkForce true;
        "net-vm".autostart = lib.mkForce true;
        "chromium-vm".autostart = lib.mkForce true;
      };
    };

  # A/B verity boot targets: LVM-based A/B slots + UKI instead of the sd-card
  # format module
  orinVerityModules = [
    jetpack-nixos.nixosModules.default
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-profiles-orin
    self.nixosModules.profiles
    orinCrosvmModule
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/verity-image.nix
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/partition-template-verity.nix
    inputs.nix-store-veritysetup-generator.nixosModules.ghaf-store-veritysetup-generator
    ../../modules/partitioning/verity-volume.nix
    ../../modules/partitioning/firstboot-persist.nix
    # Enable dm-verity and erofs in the kernel (not in the BSP default config)
    {
      boot.kernelPatches = [
        {
          name = "dm-verity-support";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            DM_VERITY = module;
            DM_CRYPT = module; # encrypted swap (randomEncryption)
            EROFS_FS = module;
            EROFS_FS_ZIP = yes; # lz4 compression support (lz4 is default, auto-selects LZ4_DECOMPRESS)
            # TODO: switch to zstd when kernel >= 6.10 (EROFS_FS_ZIP_ZSTD, commit 7c35de4df105)
          };
        }
      ];
    }
  ];

  # Non-verity Orin configurations using mkGhafConfiguration
  target-configs = [
    # ============================================================
    # Debug Configurations
    # ============================================================

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
      variant = "debug";
      extraModules = commonModules ++ [ linux71PkvmHostModule ];
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
      vmConfig = {
        sysvms.adminvm.extraModules = [ linux71PkvmGuestModule ];
        sysvms.netvm.extraModules = [ netvmCrosvmVgicItsModule ];
        appvms.chromium.extraModules = [ linux71PkvmGuestModule ];
        appvms.flatpak.extraModules = [ linux71PkvmGuestModule ];
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx64";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx64;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx-industrial";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx-industrial;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-nx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-nx;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
        # Crucial for Orin devices to use the correct render device
        # Also needs 'mesa' to be in hardware.graphics.extraPackages
        graphics.cosmic.renderDevice = "/dev/dri/renderD128";
      };
      vmConfig = {
        sysvms.netvm = {
          # 4 vCPUs is the minimum that keeps QEMU USB emulation (libusb
          # redirection of the ethernet dongle) from starving when alloy, givc
          # node + stunnel, and spire-agent are all active on Orin NX. At 2 vCPUs
          # the xhci_hcd guest driver desyncs with the QEMU event ring under load
          # ("Transfer event TRB DMA ptr not part of current TD" + NETDEV WATCHDOG
          # TX timeouts). AGX is unaffected because it has more cores per slice.
          vcpu = 4;
          # 2GB headroom: alloy + stunnel + spire-agent + givc-agent + auditd
          # pile up on net-vm with the givc/logging stack enabled, and the
          # 1GB default OOMs during the first-boot burst on Orin NX. The kernel
          # then evicts page cache backing the USB-eth driver and the dongle
          # disconnects, killing sshd on the test-net IP.
          mem = 2048;
        };
      };
    })

    # ============================================================
    # Release Configurations
    # ============================================================

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx64";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx64;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx-industrial";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx-industrial;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-nx";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-nx;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
        # Crucial for Orin devices to use the correct render device
        # Also needs 'mesa' to be in hardware.graphics.extraPackages
        graphics.cosmic.renderDevice = "/dev/dri/renderD128";
      };
    })

  ];

  # A/B Verity Boot Configurations (AGX only)
  verity-target-configs =
    map
      (
        variant:
        (ghaf-configuration {
          name = "nvidia-jetson-orin-agx-verity";
          inherit system;
          profile = "orin";
          hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
          inherit variant;
          extraModules = orinVerityModules;
          extraConfig = {
            reference.profiles.mvp-orinuser-trial.enable = true;
            partitioning.verity.enable = true;
            partitioning.verity.uki-signing-key-dir = lib.mkIf (
              variant == "debug"
            ) ../../modules/secureboot/dev-keys;
            hardware.nvidia.orin.secureboot.enable = true;
            # Debug builds enroll the dev certs so they match the dev signing
            # keys; release builds keep the production certs from keysSource.
            hardware.nvidia.orin.secureboot.keysSource = lib.mkIf (
              variant == "debug"
            ) ../../modules/secureboot/dev-keys;
          };
        })
        // {
          isVerity = true;
        }
      )
      [
        "debug"
        "release"
      ];
  all-target-configs = target-configs ++ verity-target-configs;

  pkvmDebugTarget =
    let
      baseTarget = lib.findFirst (
        target: target.name == "nvidia-jetson-orin-agx-debug"
      ) (throw "AGX debug target not found") target-configs;
    in
    baseTarget
    // rec {
      name = "nvidia-jetson-orin-agx-accelerated-guivm-pkvm-debug";
      hostConfiguration = baseTarget.hostConfiguration.extendModules {
        modules = [ pkvmDebugModule ];
      };
      package = hostConfiguration.config.system.build.ghafImage;
    };

  generate-nodemoapps =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-nodemoapps";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          { ghaf.reference.host-demo-apps.demo-apps.enableDemoApplications = lib.mkForce false; }
        ];
      };
      package = hostConfiguration.config.system.build.ghafImage;
    };

  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ self.nixosModules.cross-compilation-from-x86_64 ];
      };
      package = lazyPackage name hostConfiguration.config.system.build.ghafImage;
    };

  generate-luks =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-luks";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            ghaf.hardware.nvidia.orin.diskEncryption.enable = true;
            ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.enable = true;
          }
        ];
      };
      package = hostConfiguration.config.system.build.ghafImage;
    };

  generate-luks-uki =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-luks-uki";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            ghaf.hardware.nvidia.orin.diskEncryption.enable = true;
            ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.enable = true;
            ghaf.image.sdcard.uki.enable = true;
          }
        ];
      };
      package = hostConfiguration.config.system.build.ghafImage;
    };

  # LUKS and dm-verity are mutually exclusive root strategies (see the assertion
  # in jetson-orin.nix), so the verity targets get no -luks variant.
  luksable-target-configs = builtins.filter (t: !isVerityTarget t) all-target-configs;

  # Add nodemoapps targets
  targets =
    all-target-configs
    ++ (map generate-nodemoapps all-target-configs)
    ++ (map generate-luks luksable-target-configs)
    ++ (map generate-luks-uki luksable-target-configs)
    ++ (map (t: generate-luks (generate-nodemoapps t)) luksable-target-configs)
    ++ (map (t: generate-luks-uki (generate-nodemoapps t)) luksable-target-configs)
    ++ [ pkvmDebugTarget ];
  crossTargets = map generate-cross-from-x86_64 targets;
  flashTarget =
    t: qspiOnly:
    let
      innerName = t.hostConfiguration.config.hardware.nvidia-jetpack.name;
      noSB =
        (t.hostConfiguration.extendModules {
          modules = [
            (
              {
                ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
              }
              // lib.optionalAttrs (lib.strings.hasInfix "nx" t.name && !qspiOnly) {
                # NX boots from USB or NVMe; the flash script targets NVMe.
                ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDisk = lib.mkForce "nvme0n1";
                ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDiskEspPartition = lib.mkForce "nvme0n1p1";
                ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDiskRootfsPartition = lib.mkForce "nvme0n1p2";
              }
            )
          ];
        }).pkgs.nvidia-jetpack.signedFlashScript;
      withSB =
        (t.hostConfiguration.extendModules {
          modules = [
            (
              {
                ghaf.hardware.nvidia.orin.secureboot.enable = lib.mkForce true;
                ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
              }
              // lib.optionalAttrs (lib.strings.hasInfix "nx" t.name && !qspiOnly) {
                # NX boots from USB or NVMe; the flash script targets NVMe.
                ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDisk = lib.mkForce "nvme0n1";
                ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDiskEspPartition = lib.mkForce "nvme0n1p1";
                ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDiskRootfsPartition = lib.mkForce "nvme0n1p2";
              }
            )
          ];
        }).pkgs.nvidia-jetpack.signedFlashScript;
    in
    # Single `*-flash-script` entrypoint that picks between two
    # pre-built QSPI firmware variants at flash time.
    #
    # Why two variants instead of one profile-level toggle:
    #
    # `ghaf.hardware.nvidia.orin.secureboot.enable` is evaluated at Nix
    # build time. When true, it bakes the `UefiDefaultSecurityKeys`
    # device-tree overlay and PK/KEK/db ESLs into the QSPI firmware, so
    # the device enrolls keys and turns Secure Boot on at first boot.
    # Flipping it on unconditionally in the Orin profile would brick the
    # default unsigned flash path: the QSPI carries enrollment material
    # but BOOTAA64.EFI is unsigned, leaving the board in the UEFI
    # Interactive Shell with no recoverable boot entry.
    #
    # The QSPI variant has to be selected *before* the inner script runs
    # (it cannot be influenced at run time), which is what the wrapper
    # does on its own `--secure-boot` flag:
    #
    #   - default        → unsigned QSPI (no DTBO, no ESLs)
    #   - --secure-boot  → SB-enabled QSPI (DTBO + ESLs); pair it with a
    #                      *signed* sd-image via `-s`, or the enrolled
    #                      firmware will refuse the unsigned BOOTAA64.EFI
    #                      and fall through to PXE/UEFI shell.
    #
    # `-s/--signed-sd-image` itself is deliberately NOT the selector:
    # with `appPartitionSizeBytes` set the flash script carries no
    # embedded image and `-s` is how *every* flash (signed or not)
    # supplies one, so keying Secure Boot off it bricked all unsigned
    # flashes.
    #
    # Use the `-u` flag if the image contains a UKI.
    #
    # Both variants share substituted store paths (jetpack-nixos
    # `flashScript` is a thin wrapper around the same per-target
    # derivations), so the second build is mostly a Nix-eval cost.
    pkgsX86.writeShellApplication {
      name = "flash-ghaf-host";
      text = ''
        sb=0
        args=()
        for arg in "$@"; do
          case "$arg" in
            --secure-boot) sb=1 ;;
            *) args+=("$arg") ;;
          esac
        done
        if [ "$sb" = 1 ]; then
          exec ${withSB}/bin/flash-signed-${innerName} "''${args[@]}"
        else
          exec ${noSB}/bin/flash-signed-${innerName} "''${args[@]}"
        fi
      '';
    };

  # Filter verity targets without forcing every hostConfiguration.config during
  # package-set evaluation.
  isVerityTarget = t: t.isVerity or false;
  verityCrossTargets = builtins.filter isVerityTarget crossTargets;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets)
    );

    packages = {
      aarch64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets)
        // builtins.listToAttrs (
          map (
            t:
            #Note: secureTarget does not toggle between secureboot on/off!!
            lib.nameValuePair "${t.name}-flash-script" (
              lazyPackage "${t.name}-flash-script" (flashTarget t false)
            )
          ) crossTargets
        )
        // builtins.listToAttrs (
          map (
            t:
            #Note: secureTarget does not toggle between secureboot on/off!!
            lib.nameValuePair "${t.name}-flash-qspi" (lazyPackage "${t.name}-flash-qspi" (flashTarget t true))
          ) crossTargets
        )
        # OTA update artifacts for verity targets
        // builtins.listToAttrs (
          map (
            t: lib.nameValuePair "${t.name}-ghafImage" t.hostConfiguration.config.system.build.ghafImage
          ) verityCrossTargets
        );
    };
  };
}
