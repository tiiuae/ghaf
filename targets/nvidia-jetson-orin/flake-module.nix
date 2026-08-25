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
        hardware.nvidia.orin.crosvm.enable = true;
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
        hardware.nvidia.orin.crosvm.enable = true;
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
          # `extraConfig` above sets `hardware.nvidia.orin.secureboot.enable = true`
          # unconditionally, so `flashTarget`'s `mkForce true` would yield the same
          # value and a bit-identical derivation -- at the cost of a second full
          # Jetson fixpoint (several GB of eval). Keep this in sync with that line.
          secureBootAlwaysOn = true;
        }
      )
      [
        "debug"
        "release"
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
