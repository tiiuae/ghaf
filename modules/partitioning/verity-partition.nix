# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  roothashPlaceholder = "61fe0f0c98eff2a595dd2f63a5e481a0a25387261fa9e34c37e3a4910edf32b8";
  cfg = config.ghaf.partitioning.verity;
  encryptionInteractive = config.ghaf.storage.encryption.interactiveSetup;

  # First-boot initrd service that creates LVM on the raw data partition.
  # On subsequent boots (LVM already present) the service is a no-op.
  dataInitScript = pkgs.writeShellApplication {
    name = "verity-data-init";
    runtimeInputs = with pkgs; [
      lvm2
      util-linux
      btrfs-progs
      coreutils
      systemd
    ];
    text = ''
      DATA_PART="/dev/disk/by-partlabel/data"

      # Wait for data partition device
      echo "verity-data-init: Waiting for $DATA_PART..."
      for _ in {1..30}; do
        [ -e "$DATA_PART" ] && break
        sleep 1
      done

      if [ ! -e "$DATA_PART" ]; then
        echo "verity-data-init: Data partition not found, skipping."
        exit 0
      fi

      # Determine target device: LUKS-opened mapper if present, otherwise raw
      if [ -e /dev/mapper/crypted ]; then
        TARGET=/dev/mapper/crypted
      else
        TARGET="$DATA_PART"
      fi

      # Check if LVM is fully initialized (PV + VG + both LVs)
      if pvs "$TARGET" >/dev/null 2>&1 \
         && lvs pool/swap >/dev/null 2>&1 \
         && lvs pool/persist >/dev/null 2>&1; then
        echo "verity-data-init: LVM already initialized on $TARGET, skipping."
        exit 0
      fi

      # Clean up any partial/stale LVM state before (re)initializing
      if vgs pool >/dev/null 2>&1; then
        echo "verity-data-init: Removing partial/stale VG 'pool'..."
        vgchange -an pool 2>/dev/null || true
        vgremove -f pool 2>/dev/null || true
      fi
      if pvs "$TARGET" >/dev/null 2>&1; then
        echo "verity-data-init: Removing stale PV on $TARGET..."
        pvremove -f "$TARGET" 2>/dev/null || true
      fi

      echo "verity-data-init: Initializing LVM on $TARGET..."

      # Create Physical Volume, Volume Group, and Logical Volumes
      pvcreate -f "$TARGET"
      vgcreate pool "$TARGET"
      # Swap: 12G fixed
      lvcreate -L 12G -n swap pool -y
      # Persist: 2G initially (not 100%FREE — leaves headroom for PV shrink
      # during deferred encryption)
      lvcreate -L 2G -n persist pool -y

      # Format filesystems
      echo "verity-data-init: Formatting swap..."
      mkswap -L swap /dev/pool/swap

      echo "verity-data-init: Formatting persist (btrfs)..."
      mkfs.btrfs -f -L persist /dev/pool/persist

      # Create required directories on persist
      mkdir -p /tmp/verity-data-init-mnt
      mount /dev/pool/persist /tmp/verity-data-init-mnt
      mkdir -p /tmp/verity-data-init-mnt/storagevm
      umount /tmp/verity-data-init-mnt
      rmdir /tmp/verity-data-init-mnt

      echo "verity-data-init: LVM initialization complete."
    '';
  };
in
{
  _file = ./verity-partition.nix;

  options.ghaf.partitioning.verity = {
    enable = lib.mkEnableOption "the verity (image-based) partitioning scheme";

    split = lib.mkOption {
      description = "Whether to split the partitions to separate files instead of a single image";
      type = lib.types.bool;
      default = false;
    };

    sysupdate = lib.mkOption {
      description = "Enable systemd sysupdate";
      type = lib.types.bool;
      default = false;
    };

    version = lib.mkOption {
      description = "Version string for the image, partition labels, and UKI filenames (used by sysupdate for A/B version matching)";
      type = lib.types.str;
      default = "0.0.1";
    };

    updateUrl = lib.mkOption {
      description = "Base URL for systemd-sysupdate to fetch update artifacts";
      type = lib.types.str;
      default = "https://github.com/tiiuae/ghaf/releases/latest/download";
    };

    bSlotSize = lib.mkOption {
      description = "Size of the B root partition slot. Must be large enough to hold the EROFS root. Targets can override per-hardware.";
      type = lib.types.str;
      default = "4G";
    };

    deltaUpdate = {
      enable = lib.mkEnableOption "content-addressed delta updates (replaces sysupdate for root/verity)";

      manifestUrl = lib.mkOption {
        description = "URL to the version manifest.json on the update server";
        type = lib.types.str;
        default = "${cfg.updateUrl}/manifest.json";
      };

      chunkStoreUrl = lib.mkOption {
        description = "Base URL of the HTTP chunk store";
        type = lib.types.str;
        default = "${cfg.updateUrl}/chunks";
      };

      chunkSize = lib.mkOption {
        description = "Content-defined chunk size for desync (e.g. 64K, 128K)";
        type = lib.types.str;
        default = "64K";
      };
    };
  };

  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/system/boot/uki.nix"
  ];

  config = lib.mkIf cfg.enable {
    ghaf.partitioning.btrfs-postboot.enable = true;

    ghaf.storage.encryption.partitionDevice = lib.mkDefault "/dev/disk/by-partlabel/data";

    # Verity always defers encryption — pre-encrypted LUKS at build time inflates
    # the image (encrypted random data doesn't compress).
    ghaf.storage.encryption.deferred = lib.mkIf config.ghaf.storage.encryption.enable (
      lib.mkDefault true
    );

    system.build.ghafImage = config.system.build.image.overrideAttrs (oldAttrs: {
      nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
        pkgs.jq
        pkgs.python3
      ];
      postInstall = ''
                # Extract the roothash from the JSON
                repartRoothash="$(
                  ${lib.getExe pkgs.jq} -r \
                    '[.[] | select(.roothash != null)] | .[0].roothash' \
                    "$out/repart-output.json"
                )"

                # Replace the placeholder with the real roothash in the target .raw file.
                # The raw image is tens of GB so we use a streaming Python script that
                # reads in 1 MiB chunks (constant memory) instead of sed/grep which
                # would load the entire binary file into memory and trigger OOM.
                rawFile="$out/${oldAttrs.pname}_${oldAttrs.version}.raw"
                python3 -c "
        import sys
        needle = sys.argv[1].encode()
        repl   = sys.argv[2].encode()
        fname  = sys.argv[3]
        BUF    = 1 << 20
        tail   = b\"\"
        offset = 0
        with open(fname, 'r+b') as f:
            while True:
                chunk = f.read(BUF)
                if not chunk:
                    break
                window = tail + chunk
                idx = window.find(needle)
                if idx >= 0:
                    pos = offset - len(tail) + idx
                    f.seek(pos)
                    f.write(repl)
                    print('Patched roothash at byte offset ' + str(pos))
                    sys.exit(0)
                tail = window[-(len(needle) - 1):]
                offset += len(chunk)
        print('ERROR: roothash placeholder not found', file=sys.stderr)
        sys.exit(1)
                " '${roothashPlaceholder}' "$repartRoothash" "$rawFile"

                # Compress the image
                ${pkgs.zstd}/bin/zstd --compress "$rawFile"
                rm -f "$out"/*.raw
      '';
    });

    image.repart.split = cfg.split;
    image.repart.version = cfg.version;

    boot = {
      kernelParams = [
        "roothash=${roothashPlaceholder}"
        "systemd.verity_root_options=panic-on-corruption"
      ]
      ++ lib.optional (!encryptionInteractive) "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1";

      # No bootloaders needed yet
      loader = {
        grub.enable = false;
        systemd-boot.enable = lib.mkForce false;
      };

      # Enable dm-verity and compress initrd
      initrd = {
        systemd = {
          enable = true;
          dmVerity.enable = true;

          storePaths = [
            pkgs.lvm2
            pkgs.util-linux
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.systemd
            dataInitScript
          ];

          services = {
            # First-boot LVM initialization on the raw data partition
            verity-data-init = {
              description = "Initialize LVM on verity data partition";

              wantedBy = [ "initrd.target" ];
              before = [
                "sysroot.mount"
                "initrd-root-fs.target"
              ];
              after = [
                "systemd-udevd.service"
                "systemd-cryptsetup@crypted.service"
              ];

              unitConfig = {
                DefaultDependencies = false;
              };

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = lib.getExe dataInitScript;
                StandardOutput = "journal+console";
                StandardError = "journal+console";
              };
            };

            # Ensure first-boot-encrypt (from deferred-disk-encryption.nix)
            # runs after LVM is initialized
            first-boot-encrypt = lib.mkIf config.ghaf.storage.encryption.deferred {
              after = [ "verity-data-init.service" ];
            };
          };
        };

        compressor = "zstd";
        compressorArgs = [ "-6" ];

        supportedFilesystems = {
          btrfs = true;
          erofs = true;
          vfat = true;
        };

        # LVM support in initrd for activating volumes on boot
        services.lvm.enable = true;
      };
    };

    environment.systemPackages = with pkgs; [
      cryptsetup
    ];

    # Enable systemd features
    ghaf.systemd = {
      withRepart = true;
      withSysupdate = true;
    };

    # System is now immutable
    system.switch.enable = false;

    swapDevices = [
      {
        device = "/dev/pool/swap";
        discardPolicy = "both";
        options = [ "nofail" ];
      }
    ];

    fileSystems =
      let
        tmpfsConfig = {
          neededForBoot = true;
          fsType = "tmpfs";
        };
      in
      {
        "/" = {
          fsType = "erofs";
          # for systemd-remount-fs
          options = [ "ro" ];
          device = "/dev/mapper/root";
        };

        "/persist" = {
          device = "/dev/pool/persist";
          fsType = "btrfs";
        };
      }
      // builtins.listToAttrs (
        map
          (pathDir: {
            name = pathDir;
            value = tmpfsConfig;
          })
          [
            "/bin" # /bin/sh symlink needs to be created
            "/etc"
            "/home"
            "/root"
            "/tmp"
            "/usr" # /usr/bin/env symlink needs to be created
            "/var"
          ]
      );
  };
}
