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

  # All Orin configurations using mkGhafConfiguration
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

    # ============================================================
    # A/B Verity Boot Configurations (AGX only)
    # ============================================================
  ]
  ++
    map
      (
        variant:
        ghaf-configuration {
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
        }
      )
      [
        "debug"
        "release"
      ];

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

  # Add nodemoapps targets
  targets = target-configs ++ (map generate-nodemoapps target-configs);
  crossTargets = map generate-cross-from-x86_64 targets;
  secureTarget =
    t: qspiOnly:
    let
      innerName = t.hostConfiguration.config.hardware.nvidia-jetpack.name;
      # sd-image flashScript for this target, with any extra modules layered on
      # top of the shared sd-image module set. noSB/withSB differ only by the
      # secureboot override.
      mkFlashScript =
        extraModules:
        (t.hostConfiguration.extendModules {
          modules = [
            ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/sdimage.nix
            ../../modules/reference/hardware/jetpack/nvidia-jetson-orin/partition-template.nix
            {
              ghaf.hardware.nvidia.orin.flashScriptOverrides.method = "sdimage";
              ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = qspiOnly;
            }
          ]
          ++ extraModules;
        }).pkgs.nvidia-jetpack.flashScript;
      noSB = mkFlashScript [ ];
      withSB = mkFlashScript [
        { ghaf.hardware.nvidia.orin.secureboot.enable = lib.mkForce true; }
      ];
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
    # `-s/--signed-sd-image` is a *runtime* flag on the flash script: it
    # only swaps in a signed BOOTAA64.EFI / kernel staged from a signed
    # sd-image, it cannot influence the QSPI firmware that was already
    # produced at Nix evaluation time. So the QSPI variant has to be
    # selected *before* the script runs, which is what the wrapper does:
    #
    #   - no `-s`  → unsigned QSPI (no DTBO, no ESLs) + unsigned BOOTAA64.EFI
    #   - with `-s` → SB-enabled QSPI (DTBO + ESLs) + signed BOOTAA64.EFI
    #
    # Both variants share substituted store paths (jetpack-nixos
    # `flashScript` is a thin wrapper around the same per-target
    # derivations), so the second build is mostly a Nix-eval cost.
    pkgsX86.writeShellApplication {
      name = "flash-ghaf-host";
      text = ''
        signed=0
        for arg in "$@"; do
          case "$arg" in
            -s|--signed-sd-image) signed=1 ;;
          esac
        done
        if [ "$signed" = 1 ]; then
          exec ${withSB}/bin/flash-${innerName} "$@"
        else
          exec ${noSB}/bin/flash-${innerName} "$@"
        fi
      '';
    };

  # Initrd flash script with only-QSPI firmware flashing (no eMMC boot/root).
  initrdQspi =
    t:
    (t.hostConfiguration.extendModules {
      modules = [
        { ghaf.hardware.nvidia.orin.flashScriptOverrides.onlyQSPI = true; }
      ];
    }).pkgs.nvidia-jetpack.initrdFlashScript;

  # Partition cross-targets by verity-volume in one pass. Verity targets use
  # partition-template-verity.nix (LVM-based A/B flash), not
  # sdimage.nix/partition-template.nix. Extending them with the old sd-image
  # modules would double-define fileSystems."/boot", so the per-target flash
  # entrypoints below are emitted only for non-verity targets; verity targets
  # get the OTA -ghafImage output instead.
  isVerityTarget = t: (t.hostConfiguration.config.ghaf.partitioning.verity.enable or false);
  crossTargetsByVerity = lib.partition isVerityTarget crossTargets;
  verityCrossTargets = crossTargetsByVerity.right;
  nonVerityCrossTargets = crossTargetsByVerity.wrong;

  # Per-cross-target flash package variants: name suffix -> derivation builder.
  # Old sd-image flow (dev/CI: dd to external USB/SD storage) + new two-stage
  # initrd flow (production: flash internal eMMC). Emitted for non-verity only.
  flashVariants = [
    {
      suffix = "flash-script";
      drv = t: secureTarget t false;
    }
    {
      suffix = "flash-qspi";
      drv = t: secureTarget t true;
    }
    {
      suffix = "flash-initrd";
      drv = t: t.hostConfiguration.pkgs.nvidia-jetpack.initrdFlashScript;
    }
    {
      suffix = "flash-initrd-qspi";
      drv = initrdQspi;
    }
    {
      # ESP + root image set with flash-manifest.json for external CI / hw-test.
      suffix = "flash-images";
      drv = t: t.hostConfiguration.config.system.build.ghafFlashImages;
    }
  ];
  flashPackages = builtins.listToAttrs (
    lib.concatMap (
      v:
      map (
        t:
        let
          name = "${t.name}-${v.suffix}";
        in
        lib.nameValuePair name (lazyPackage name (v.drv t))
      ) nonVerityCrossTargets
    ) flashVariants
  );
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
        # Per-target flash entrypoints: sd-image dev flow + initrd production flow
        // flashPackages
        # OTA update artifacts for verity targets
        // builtins.listToAttrs (
          map (
            t: lib.nameValuePair "${t.name}-ghafImage" t.hostConfiguration.config.system.build.ghafImage
          ) verityCrossTargets
        );
    };
  };
}
