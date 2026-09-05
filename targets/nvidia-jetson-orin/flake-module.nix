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

  # Common modules shared across all Orin configurations
  commonModules = orinSpecificModules ++ [
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-profiles-orin
    self.nixosModules.profiles
  ];

  # Exercise the complete manager/CDI integration in an existing CI-built
  # image without making example workloads part of Ghaf. The manager-owned
  # mock plugin is sufficient for build and boot validation; downstream
  # configurations replace this default with real workload plugins.
  nxGpuPartitioningDebugModule =
    { pkgs, ... }:
    let
      managerSdk = inputs.gpu-partition-manager.lib.mkSdk { inherit pkgs; };
      managerMockPlugin = pkgs.stdenv.mkDerivation {
        pname = "gpu-partition-manager-mock-plugin";
        version = "1.0";

        dontUnpack = true;
        dontConfigure = true;

        buildPhase = ''
          runHook preBuild
          $CC -std=c11 -Wall -Wextra -Werror -fPIC -shared \
            -I${managerSdk}/include \
            -I${pkgs.nvidia-jetpack.cudaPackages.cuda_cudart}/include \
            ${inputs.gpu-partition-manager}/tests/mock-plugin.c \
            -o plugin.so
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm755 plugin.so \
            $out/lib/gpu-partition-manager/plugin.so
          runHook postInstall
        '';

        passthru = {
          gpuPartitionPluginName = "mock";
          requiredPluginAbiVersion = managerSdk.pluginAbiVersion;
        };

        meta = {
          description = "Manager-owned mock plugin for NX debug integration validation";
          platforms = [ "aarch64-linux" ];
        };
      };
    in
    {
      ghaf.hardware.nvidia.passthroughs.gpu_vm = {
        containerRuntime.enable = true;
        partitionManager = {
          enable = true;
          plugins = lib.mkDefault [ managerMockPlugin ];
        };
      };
    };

  # A/B verity boot targets: LVM-based A/B slots + UKI instead of the sd-card
  # format module
  orinVerityModules = [
    jetpack-nixos.nixosModules.default
    self.nixosModules.reference-host-demo-apps
    self.nixosModules.reference-profiles-orin
    self.nixosModules.profiles
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/verity-image.nix
    ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/partition-template-verity.nix
    self.nixosModules.secure-ab-core
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

  mkOrinSecureUpdateModule =
    target:
    {
      config,
      ...
    }:
    {
      ghaf = {
        partitioning.verity = {
          # Both Orin variants have room for two 12 GiB roots on the 64 GB AGX
          # eMMC while retaining roughly 30 GiB for persist. Current signed
          # canaries use less than 5 GiB of root data and 40 MiB of verity data.
          rootSlotSizeMiB = 12 * 1024;
          veritySlotSizeMiB = 256;
        };
        secureUpdate = {
          enable = true;
          inherit target;
        };
        hardware.nvidia.orin.secureboot = {
          inherit (config.ghaf.secureUpdate) publicTrustDigests;
          certificateContents = config.ghaf.secureUpdate.uefiCertificateContents;
        };
      };
    };

  orinLocalBootFirstModule =
    { pkgs, ... }:
    {
      # NVIDIA's development firmware can put HTTP/PXE entries before the
      # internal storage entry. That turns every watchdog reset into a
      # multi-minute network-boot timeout and, more importantly, delays A/B
      # attempt consumption. Promote only the storage entry that successfully
      # booted this system; never promote a shell, setup, or network entry.
      systemd.services.ghaf-promote-local-uefi-boot = {
        description = "Promote the booted internal storage UEFI entry";
        after = [
          "boot.mount"
          "setup-jetson-efi-variables.service"
        ];
        requires = [ "boot.mount" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          coreutils
          efibootmgr
          gnugrep
          gnused
        ];
        script = ''
          state="$(efibootmgr)"
          current="$(printf '%s\n' "$state" | sed -n 's/^BootCurrent:[[:space:]]*//p')"
          order="$(printf '%s\n' "$state" | sed -n 's/^BootOrder:[[:space:]]*//p')"

          if ! printf '%s\n' "$current" | grep -Eq '^[0-9A-Fa-f]{4}$'; then
            echo "Cannot identify current UEFI boot entry: $current" >&2
            exit 1
          fi

          label="$(
            printf '%s\n' "$state" \
              | sed -n "s/^Boot''${current}\\*\{0,1\}[[:space:]]*//p" \
              | head -n1
          )"
          case "$label" in
          "UEFI HTTP"* | "UEFI PXE"* | "UEFI Shell"* | "Enter Setup"* | "BootManagerMenuApp"* | "")
            echo "Refusing to promote non-storage UEFI entry Boot$current: $label" >&2
            exit 1
            ;;
          "UEFI "*) ;;
          *)
            echo "Refusing to promote unrecognized UEFI entry Boot$current: $label" >&2
            exit 1
            ;;
          esac

          first="''${order%%,*}"
          if [ "$first" = "$current" ]; then
            echo "Boot$current ($label) is already first in BootOrder"
            exit 0
          fi

          newOrder="$current"
          oldIFS="$IFS"
          IFS=,
          for entry in $order; do
            if [ "$entry" != "$current" ]; then
              newOrder="$newOrder,$entry"
            fi
          done
          IFS="$oldIFS"

          efibootmgr --bootorder "$newOrder"
          echo "Promoted Boot$current ($label) ahead of network boot entries"
        '';
        serviceConfig.Type = "oneshot";
      };
    };

  # Static HTTP is a deliberately manual development transport. Keep its
  # download/parsing tools in the secure canary net-vm, which owns external
  # networking, rather than giving the Ghaf host direct network access.
  orinUpdateHttpFetchModule =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        curl
        jq
      ];
    };

  # Shared by the AGX and NX accelerated-guivm variants.
  acceleratedGuivmUsbRules = [

    {
      description = "USB Devices for GUIVM";
      targetVm = "gui-vm";
      allow = [
        {
          interfaceClass = 3;
          interfaceProtocol = 1;
          description = "HID Keyboard";
        }
        {
          interfaceClass = 3;
          interfaceProtocol = 2;
          description = "HID Mouse";
        }
        {
          interfaceClass = 11;
          description = "Chip/SmartCard (e.g. YubiKey)";
        }
        {
          interfaceClass = 8;
          interfaceSubclass = 6;
          description = "Mass Storage - SCSI (USB drives)";
        }
        {
          interfaceClass = 17;
          description = "USB-C alternate modes supported by device";
        }
      ];
      deny = [
        {
          vendorId = "046d";
          productId = "c52b";
          description = "Logitech Unifying Receiver: evdev-only on Orin (usb-host interrupt-IN broken)";
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
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-agx-accelerated-guivm";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
        # Accelerated topology has one combined GPU/display owner.
        hardware.nvidia.passthroughs.gui_vm.enable = true;
        hardware.nvidia.passthroughs.gpu_vm.enable = lib.mkForce false;
        hardware.nvidia.passthroughs.disp_vm.enable = lib.mkForce false;

        # Keep the Unifying receiver on the working evdev path.
        hardware.passthrough.usb.guivmRules = lib.mkForce acceleratedGuivmUsbRules;
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
      extraModules = commonModules ++ [ nxGpuPartitioningDebugModule ];
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
        # The split topology reserves ~2.1GiB after dropping the old 4GiB VRAM
        # bank. Keep the VM total at or under 7GiB until this reduced layout is
        # validated on NX; 10.1GiB under the former ~6.1GiB layout OOM-killed a
        # VM and hung PID 1 on every boot.
        sysvms.gpuvm = {
          mem = 2048;
        };
        # disp-vm runs on the 1:1 dispram carveout; -m only backs the
        # machine's default RAM window.
        sysvms.dispvm = {
          mem = 1536;
        };
      };
    })

    (ghaf-configuration {
      name = "nvidia-jetson-orin-nx-accelerated-guivm";
      inherit system;
      profile = "orin";
      hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-nx;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-orinuser-trial.enable = true;
        # Accelerated topology has one combined GPU/display owner.
        hardware.nvidia.passthroughs.gui_vm.enable = true;
        hardware.nvidia.passthroughs.gpu_vm.enable = lib.mkForce false;
        hardware.nvidia.passthroughs.disp_vm.enable = lib.mkForce false;

        # Pin APP so the flash script carries no embedded image: every flash
        # supplies one with -s, which also keeps the script buildable without
        # the image.
        hardware.nvidia.orin.flashScriptOverrides.appPartitionSizeBytes = 34359738368;

        # Keep the Unifying receiver on the working evdev path.
        hardware.passthrough.usb.guivmRules = lib.mkForce acceleratedGuivmUsbRules;
      };
      vmConfig = {
        sysvms.netvm = {
          vcpu = 4;
          mem = 2048;
        };
        # VFIO pins all guest RAM up front, so 4096 only fits alongside the
        # host zram in orin-nx.nix; without it this OOM-crash-looped.
        sysvms.guivm = {
          mem = 4096;
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

  # Secure A/B verity+LUKS canaries. The AGX canary leaves the firmware TPM
  # disabled: its OP-TEE fTPM probe can remain uninterruptibly blocked and
  # prevent reboot. This does not disable the separate OP-TEE DUK path used to
  # unlock APP.
  verity-target-configs =
    map
      (
        board:
        (ghaf-configuration {
          name = "${board.name}-verity-luks";
          inherit system;
          profile = "orin";
          inherit (board) hardwareModule;
          variant = "debug";
          extraModules = orinVerityModules ++ [
            (mkOrinSecureUpdateModule "${board.name}-verity-luks-debug")
            orinLocalBootFirstModule
            {
              # The Tegra186 watchdog used by Orin accepts timeouts up to
              # 255s. Arm it in both initrd and stage 2 so verity panics,
              # early boot hangs, and shutdown hangs can consume a
              # boot-counting attempt. systemd's 10 minute reboot-watchdog
              # default is rejected by this device, so keep all configured
              # timeouts within its range.
              # NixOS' initrd panic-on-fail service triggers a SysRq crash
              # when emergency.target is reached. Together with panic=10,
              # this makes an unmountable or corrupted trial consume its
              # systemd-boot attempt instead of waiting in an emergency
              # shell while PID 1 continues to feed the watchdog.
              boot.kernelParams = [
                "boot.panic_on_fail"
                "panic=10"
              ];
              boot.initrd.systemd.settings.Manager = {
                WatchdogDevice = "/dev/watchdog0";
                RuntimeWatchdogSec = "30s";
                RebootWatchdogSec = "2min";
              };
              systemd.settings.Manager = {
                WatchdogDevice = "/dev/watchdog0";
                RuntimeWatchdogSec = "30s";
                RebootWatchdogSec = "2min";
              };
            }
          ];
          extraConfig = {
            reference.profiles.mvp-orinuser-trial.enable = true;
            partitioning.verity.enable = true;
            # Linux 6.6 on Orin supports LZ4HC EROFS images but not the zstd
            # format emitted by the current erofs-utils.
            partitioning.verity.erofsCompression.algorithm = "lz4hc";
            hardware.nvidia.orin.secureboot.enable = true;
            hardware.nvidia.orin.diskEncryption.enable = true;
            hardware.nvidia.orin.diskEncryption.deviceUniqueKey.enable = true;
            hardware.nvidia.orin.ftpm.enable = board.enableFtpm;
            hardware.nvidia.orin.runtimeEkProvision.enable = board.enableFtpm;
            virtualization.vmConfig.sysvms.netvm.extraModules = [ orinUpdateHttpFetchModule ];
            boot-health = {
              enable = true;
              luksMapper = "cryptroot";
            };
          };
        })
        // {
          isVerity = true;
          # `extraConfig` above sets `hardware.nvidia.orin.secureboot.enable = true`
          # unconditionally, so `flashTarget`'s `mkForce true` would yield the same
          # value and a bit-identical derivation -- at the cost of a second full
          # Jetson fixpoint (several GB of eval). Keep this in sync with that line.
          secureBootAlwaysOn = true;
        }
      )
      [
        {
          name = "nvidia-jetson-orin-nx";
          hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-nx;
          enableFtpm = true;
        }
        {
          name = "nvidia-jetson-orin-agx";
          hardwareModule = self.nixosModules.hardware-nvidia-jetson-orin-agx;
          enableFtpm = false;
        }
      ];
  all-target-configs = target-configs ++ verity-target-configs;

  generate-nodemoapps =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-nodemoapps";
      # Consumed by `flashCrossTargets` below to skip generating flash attributes
      # for these; marked here rather than matched on the name, matching how
      # verity targets carry `isVerity`.
      isNoDemoApps = true;
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [
          {
            ghaf.reference = {
              host-demo-apps.demo-apps.enableDemoApplications = lib.mkForce false;
              programs.windows-launcher.enable = lib.mkForce false;
            };
          }
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

  # Secure verity canaries already contain the outer LUKS cryptpool, so do not
  # generate duplicate synthetic -luks or -luks-uki variants for them.
  luksable-target-configs = builtins.filter (t: !isVerityTarget t) all-target-configs;

  # Add nodemoapps targets
  targets =
    all-target-configs
    ++ (map generate-nodemoapps all-target-configs)
    ++ (map generate-luks luksable-target-configs)
    ++ (map generate-luks-uki luksable-target-configs)
    ++ (map (t: generate-luks (generate-nodemoapps t)) luksable-target-configs)
    ++ (map (t: generate-luks-uki (generate-nodemoapps t)) luksable-target-configs);
  crossTargets = map generate-cross-from-x86_64 targets;

  flashTarget =
    t: qspiOnly:
    let
      # Shared by both secureboot variants so the two cannot drift apart.
      nxDiskOverrides = lib.optionalAttrs (lib.strings.hasInfix "nx" t.name && !qspiOnly) {
        # NX boots from USB or NVMe; the flash script targets NVMe.
        ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDisk = lib.mkForce "nvme0n1";
        ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDiskEspPartition = lib.mkForce "nvme0n1p1";
        ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDiskRootfsPartition = lib.mkForce "nvme0n1p2";
      };
      noSBCfg = t.hostConfiguration.extendModules {
        modules = [
          (
            {
              ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
            }
            // nxDiskOverrides
          )
        ];
      };
      # Read the board name off a fixpoint that is already forced for `noSB`
      # rather than forcing `t.hostConfiguration` as a third one. The added
      # modules do not touch `som`/`carrierBoard`, so the string is identical by
      # construction. Each extra fixpoint is a full re-evaluation -- see
      # `extendModules` in nixpkgs lib/modules.nix, which shares nothing.
      innerName = noSBCfg.config.hardware.nvidia-jetpack.name;
      noSB = noSBCfg.pkgs.nvidia-jetpack.signedFlashScript;
      # Targets that already enable secureboot unconditionally get the identical
      # derivation back from `mkForce true`, so skip the second fixpoint entirely.
      withSB =
        if t.secureBootAlwaysOn or false then
          noSB
        else
          (t.hostConfiguration.extendModules {
            modules = [
              (
                {
                  ghaf.hardware.nvidia.orin.secureboot.enable = lib.mkForce true;
                  ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
                }
                // nxDiskOverrides
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

  # Targets that get their own flash attributes.
  #
  # `nodemoapps` only removes demo applications from the *image*, and no flash
  # script embeds an image any more: every Orin board pins
  # `appPartitionSizeBytes`, so flash.xml carries static ESP/APP sizes and the
  # image is supplied at run time with `-s`. The variant therefore cannot change
  # the flash script, and a census over all 125 flash attributes confirmed it --
  # 63 distinct derivations, and all 62 duplicates were exactly an
  # `X` / `X-nodemoapps` pair.
  #
  # Each duplicate cost a full Jetson derivation-graph construction during CI
  # eval, which is where the eval memory goes. Flash a `nodemoapps` image with the
  # base target's script and `-s <image>`.
  flashCrossTargets = builtins.filter (t: !(t.isNoDemoApps or false)) crossTargets;
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
          ) flashCrossTargets
        )
        // builtins.listToAttrs (
          map (
            t:
            #Note: secureTarget does not toggle between secureboot on/off!!
            lib.nameValuePair "${t.name}-flash-qspi" (lazyPackage "${t.name}-flash-qspi" (flashTarget t true))
            # `onlyQSPI` is read only by partition-template.nix, whose config is
            # gated on `!verity`; the verity partition template never reads it. A
            # verity `-flash-qspi` is therefore the same derivation as its
            # `-flash-script`, so emitting it costs a full Jetson eval for a
            # duplicate.
          ) (builtins.filter (t: !(isVerityTarget t)) flashCrossTargets)
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
