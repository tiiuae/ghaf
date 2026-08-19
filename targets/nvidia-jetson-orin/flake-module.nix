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
  updateGenerationText = builtins.getEnv "GHAF_UPDATE_GENERATION";
  updateHealthFailureText = builtins.getEnv "GHAF_AB_TEST_UNHEALTHY";
  updateGeneration =
    if updateGenerationText == "" then
      1
    else if builtins.match "^[1-9][0-9]*$" updateGenerationText == null then
      throw "GHAF_UPDATE_GENERATION must be a positive decimal integer"
    else
      builtins.fromJSON updateGenerationText;
  updateHealthFailure =
    if updateHealthFailureText == "" then
      false
    else if updateHealthFailureText == "1" then
      true
    else
      throw "GHAF_AB_TEST_UNHEALTHY must be unset or 1";
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
    inputs.nix-store-veritysetup-generator.nixosModules.ghaf-store-veritysetup-generator
    ../../modules/partitioning/verity-volume.nix
    ../../modules/partitioning/firstboot-persist.nix
    ../../modules/partitioning/boot-health.nix
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

  mkDevTrustModule =
    target:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      keyDir = builtins.getEnv "GHAF_DEV_KEY_DIR";
      requiredPublic = [
        "PK.crt"
        "KEK.crt"
        "db.crt"
        "update.pub"
      ];
      missingPublic = lib.filter (name: !builtins.pathExists "${keyDir}/${name}") requiredPublic;
      haveExternalPublic = keyDir != "" && missingPublic == [ ];
      externalPublicFile =
        name:
        builtins.path {
          path = builtins.toPath "${keyDir}/${name}";
          name = "ghaf-dev-${name}";
        };
      fallbackUefiCertDir = ../../modules/secureboot/dev-keys;
      # RFC 8032 test-vector public key 1. Its private seed is public, so this
      # key is deliberately suitable only for pure evaluation and CI builds.
      # Flashing still requires an external trust directory and never uses
      # this key to sign anything.
      fallbackUpdatePub = pkgs.runCommand "ghaf-ci-only-update.pub" { } ''
        printf '%s' '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=' \
          | ${pkgs.buildPackages.coreutils}/bin/base64 --decode > "$out"
        test "$(${pkgs.buildPackages.coreutils}/bin/wc -c < "$out")" -eq 32
      '';
      trustWarning =
        if haveExternalPublic then
          "${target}: using external public trust from GHAF_DEV_KEY_DIR; private signing keys remain outside the Nix store."
        else
          "${target}: GHAF_DEV_KEY_DIR is unset; using repository development public trust for evaluation/build only. Secure A/B flashing and update signing require GHAF_DEV_KEY_DIR from ghaf-dev-keygen; the exported flash script falls back to the generic unsigned target.";
    in
    {
      assertions = lib.optional (keyDir != "") {
        assertion = haveExternalPublic;
        message = "${target}: GHAF_DEV_KEY_DIR is set but missing required public trust files: ${lib.concatStringsSep ", " missingPublic}.";
      };
      warnings = lib.optional (keyDir == "" || haveExternalPublic) trustWarning;

      ghaf.hardware.nvidia.orin.secureboot.certificateContents =
        if haveExternalPublic then
          {
            PK = builtins.readFile "${keyDir}/PK.crt";
            KEK = builtins.readFile "${keyDir}/KEK.crt";
            db = builtins.readFile "${keyDir}/db.crt";
          }
        else
          {
            PK = builtins.readFile (fallbackUefiCertDir + "/PK.crt");
            KEK = builtins.readFile (fallbackUefiCertDir + "/KEK.crt");
            db = builtins.readFile (fallbackUefiCertDir + "/db.crt");
          };
      ghaf.hardware.nvidia.orin.secureboot.externalPublicTrustConfigured = haveExternalPublic;
      ghaf.hardware.nvidia.orin.secureboot.publicTrustDigests =
        if haveExternalPublic then
          lib.genAttrs requiredPublic (name: builtins.hashFile "sha256" "${keyDir}/${name}")
        else
          { };
      environment.etc = {
        "ghaf/update/update.pub".source =
          if haveExternalPublic then externalPublicFile "update.pub" else fallbackUpdatePub;
        "ghaf/update/db.crt".source =
          if haveExternalPublic then externalPublicFile "db.crt" else fallbackUefiCertDir + "/db.crt";
        # Keep consecutive canary generations distinct in the immutable root
        # closure so their A/B LV names cannot collide.
        "ghaf/update/generation".text = toString config.ghaf.partitioning.verity.generation;
      };
      environment.sessionVariables = {
        GHAF_UPDATE_TRUSTED_KEY = "/etc/ghaf/update/update.pub";
        GHAF_UKI_TRUSTED_CERT = "/etc/ghaf/update/db.crt";
        GHAF_UPDATE_TARGET = target;
        GHAF_ACCEPTED_GENERATION_FILE = config.ghaf.boot-health.acceptedGenerationFile;
      };
      environment.systemPackages = [ pkgs.sbsigntool ];
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
            (mkDevTrustModule "${board.name}-verity-luks-debug")
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
            partitioning.verity.target = "${board.name}-verity-luks-debug";
            partitioning.verity.generation = updateGeneration;
            hardware.nvidia.orin.secureboot.enable = true;
            hardware.nvidia.orin.diskEncryption.enable = true;
            hardware.nvidia.orin.diskEncryption.deviceUniqueKey.enable = true;
            hardware.nvidia.orin.ftpm.enable = board.enableFtpm;
            hardware.nvidia.orin.runtimeEkProvision.enable = board.enableFtpm;
            virtualization.vmConfig.sysvms.netvm.extraModules = [ orinUpdateHttpFetchModule ];
            boot-health.enable = true;
            boot-health.debugUnhealthyMicrovm =
              if updateHealthFailure then "ab-health-failure-injection" else null;
          };
        })
        // {
          isVerity = true;
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

  genericUnsignedTarget =
    t:
    let
      fallbackName = lib.replaceStrings [ "-verity-luks" ] [ "" ] t.name;
    in
    lib.findFirst (candidate: candidate.name == fallbackName)
      (throw "No generic unsigned fallback target `${fallbackName}` for secure A/B target `${t.name}`")
      crossTargets;

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

  exportedFlashTarget =
    t:
    if
      isVerityTarget t
      && !t.hostConfiguration.config.ghaf.hardware.nvidia.orin.secureboot.externalPublicTrustConfigured
    then
      let
        fallback = genericUnsignedTarget t;
        fallbackFlash = flashTarget fallback false;
      in
      pkgsX86.writeShellApplication {
        name = "flash-ghaf-host";
        text = ''
          echo "WARNING: secure A/B development trust was unavailable at evaluation; flashing the generic unsigned target instead." >&2
          echo "  Requested: ${t.name}" >&2
          echo "  Fallback:  ${fallback.name}" >&2
          echo "  Rebuild with --impure and GHAF_DEV_KEY_DIR from ghaf-dev-keygen to flash the secure A/B canary." >&2

          args=()
          while (($#)); do
            case "$1" in
              --secure-boot)
                echo "WARNING: ignoring --secure-boot because the CI-only fallback is explicitly unsigned." >&2
                shift
                ;;
              -u|--uki)
                echo "WARNING: ignoring $1 because the generic fallback does not use a UKI image." >&2
                shift
                ;;
              -s|--signed-sd-image)
                if (($# < 2)); then
                  echo "ERROR: $1 requires an image directory argument." >&2
                  exit 2
                fi
                echo "WARNING: ignoring $1 and its argument because the fallback uses its built-in generic unsigned image." >&2
                shift 2
                ;;
              *)
                args+=("$1")
                shift
                ;;
            esac
          done
          exec ${fallbackFlash}/bin/flash-ghaf-host "''${args[@]}"
        '';
      }
    else
      flashTarget t false;

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
              lazyPackage "${t.name}-flash-script" (exportedFlashTarget t)
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
