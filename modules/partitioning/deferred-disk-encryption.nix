# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Deferred disk encryption module.
#
# This module handles applying LUKS encryption on first boot rather than
# at image creation time. The workflow is:
#
# 1. Image is created with plain LVM (no encryption)
# 2. On first boot, systemd service detects unencrypted state
# 3. User is prompted for encryption password/PIN (release mode)
#    OR encryption is applied automatically (debug mode)
# 4. cryptsetup-reencrypt applies LUKS encryption in-place
# 5. TPM2/FIDO2 enrollment happens automatically
# 6. System reboots with encrypted disk
# 7. Subsequent boots use LUKS with TPM/FIDO2 unlock
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    getExe
    ;
  cfg = config.ghaf.storage.encryption;

  # Determine the LVM partition device
  # This is the partition that will be encrypted
  lvmPartition =
    if config.ghaf.partitioning.verity.enable then
      # For verity setups, use persist partition
      "/dev/disk/by-partuuid/${config.image.repart.partitions."50-persist".repartConfig.UUID}"
    else
      # For disko setups, use the luks partition (which contains LVM)
      config.disko.devices.disk.disk1.content.partitions.luks.device;

  # Script to extend persist partition after encryption
  extendPersistScript = pkgs.writeShellApplication {
    name = "extend-persist-postencrypt";
    runtimeInputs = [
      pkgs.cryptsetup
      pkgs.lvm2
      pkgs.btrfs-progs
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail

      # Resize the encrypted device to use all available space
      if cryptsetup status crypted >/dev/null 2>&1; then
        echo "Resizing encrypted device..."
        echo | cryptsetup resize crypted || true
      fi

      # Extend PV and LV
      echo "Extending physical volume..."
      pvresize /dev/mapper/crypted || true

      echo "Extending persist logical volume..."
      lvextend -l +100%FREE /dev/pool/persist || true

      # Resize btrfs filesystem
      echo "Resizing btrfs filesystem..."
      btrfs filesystem resize max /persist || true

      # Mark as complete
      touch /persist/.extend-persist-done
      sync
    '';
  };

  firstBootEncryptScript = pkgs.writeShellApplication {
    name = "first-boot-encrypt";
    runtimeInputs = [
      pkgs.cryptsetup
      pkgs.lvm2
      pkgs.systemd
      pkgs.util-linux
      pkgs.tpm2-tools
      pkgs.e2fsprogs
      pkgs.btrfs-progs
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gawk
    ];
    text = ''
      set -euo pipefail

      STATE_FILE="/persist/.encryption-applied"
      LVM_PV="${lvmPartition}"

      # Check if already encrypted
      if [ -f "$STATE_FILE" ]; then
        echo "Encryption already applied, skipping..."
        exit 0
      fi

      # Check if device is already LUKS
      if cryptsetup isLuks "$LVM_PV"; then
        echo "Device already encrypted, marking complete..."
        mount -o remount,rw /persist 2>/dev/null || true
        touch "$STATE_FILE"
        sync
        exit 0
      fi

      echo "╔════════════════════════════════════════════════════════╗"
      echo "║         First Boot - Disk Encryption Setup            ║"
      echo "╚════════════════════════════════════════════════════════╝"
      echo ""
      echo "This system will now apply full disk encryption to protect"
      echo "your data. This process is irreversible and required for"
      echo "system security."
      echo ""

      ${
        if config.ghaf.profiles.debug.enable then
          ''
            # Debug mode: automatic encryption with empty password
            echo "🔧 Debug mode: Applying encryption automatically..."
            PASSPHRASE=""
          ''
        else
          ''
            # Release mode: prompt for user password/PIN
            echo "You will be prompted to set a PIN or password."
            echo "This will be required on every boot to unlock the system."
            echo ""
            echo "Requirements:"
            echo "  - Minimum 4 characters"
            echo "  - Cannot be empty"
            echo ""

            # Read passphrase securely
            PASSPHRASE=""
            PASSPHRASE2="x"
            while [ "$PASSPHRASE" != "$PASSPHRASE2" ] || [ -z "$PASSPHRASE" ] || [ ''${#PASSPHRASE} -lt 4 ]; do
              echo -n "Enter encryption PIN/password: "
              read -rs PASSPHRASE
              echo ""

              if [ -z "$PASSPHRASE" ]; then
                echo "❌ Password cannot be empty"
                continue
              fi

              if [ ''${#PASSPHRASE} -lt 4 ]; then
                echo "❌ Password must be at least 4 characters"
                continue
              fi

              echo -n "Confirm PIN/password: "
              read -rs PASSPHRASE2
              echo ""

              if [ "$PASSPHRASE" != "$PASSPHRASE2" ]; then
                echo "❌ Passwords don't match, please try again"
                echo ""
              fi
            done

            echo "✅ Password set successfully"
          ''
      }

      echo ""
      echo "🔄 Preparing system for encryption..."

      # Ensure all filesystems are synced
      sync

      # Deactivate all LVs to prepare for encryption
      echo "📦 Deactivating logical volumes..."
      vgchange -an pool 2>/dev/null || true
      sleep 1

      # Unmount if mounted (shouldn't be at this stage but safety check)
      umount -f /persist 2>/dev/null || true
      swapoff -a 2>/dev/null || true

      echo ""
      echo "🔐 Encrypting partition..."
      echo "    This will take several minutes depending on disk size."
      echo "    Please do not power off the system!"
      echo ""

      # Encrypt the partition in-place using cryptsetup-reencrypt
      # Options:
      #   --encrypt: Convert plain device to LUKS
      #   --type luks2: Use LUKS version 2
      #   --reduce-device-size: Leave space for LUKS header
      #   --resilience journal: Use journal for crash safety
      #   --pbkdf argon2id: Use memory-hard KDF (secure against GPU attacks)
      echo -n "$PASSPHRASE" | cryptsetup reencrypt \
        --encrypt \
        --type luks2 \
        --reduce-device-size 16M \
        --resilience journal \
        --pbkdf argon2id \
        --pbkdf-memory 1048576 \
        --pbkdf-parallel 4 \
        "$LVM_PV" \
        --key-file=- || {
          echo "❌ Encryption failed!"
          exit 1
        }

      echo ""
      echo "✅ Encryption complete!"

      # Open the newly encrypted device
      echo "🔓 Opening encrypted device..."
      echo -n "$PASSPHRASE" | cryptsetup open "$LVM_PV" crypted --key-file=- || {
        echo "❌ Failed to open encrypted device!"
        exit 1
      }

      # Activate LVM on the encrypted device
      echo "📦 Activating logical volumes..."
      vgchange -ay pool || {
        echo "❌ Failed to activate volume group!"
        exit 1
      }

      # Mount persist to write state file
      mount /dev/pool/persist /mnt 2>/dev/null || true

      ${
        if cfg.backendType == "tpm2" then
          ''
            # Enroll TPM2 for automatic unlocking
            echo ""
            echo "🔑 Enrolling TPM 2.0 for automatic unlock..."

            if [ -e /dev/tpmrm0 ]; then
              # Enroll TPM with optional PIN
              if PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                --tpm2-device=auto \
                --tpm2-pcrs=7 \
                ${if config.ghaf.profiles.debug.enable then "--tpm2-with-pin=no" else "--tpm2-with-pin=yes"} \
                "$LVM_PV"; then

                # Add recovery key
                echo "🔑 Adding recovery key..."
                PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                  --recovery \
                  "$LVM_PV" || {
                    echo "⚠️  Recovery key enrollment failed"
                  }

                # Remove the password slot only if TPM enrollment succeeded
                echo "🗑️  Removing password slot..."
                systemd-cryptenroll --wipe-slot=password "$LVM_PV" || {
                  echo "⚠️  Could not remove password slot, it will remain available"
                }

                echo "✅ TPM enrollment complete!"
              else
                echo "⚠️  TPM enrollment failed!"
                echo "    Password slot will NOT be removed. You must use your password to unlock the disk."
              fi
            else
              echo "⚠️  No TPM device found, password will be required on each boot"
            fi
          ''
        else if cfg.backendType == "fido2" then
          ''
            # Enroll FIDO2 device for unlocking
            echo ""
            echo "🔑 Enrolling FIDO2 device for unlock..."

            if [ -e /dev/hidraw0 ]; then
              PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                --fido2-device=auto \
                --fido2-with-user-presence=yes \
                --fido2-with-client-pin=yes \
                "$LVM_PV" || {
                  echo "⚠️  FIDO2 enrollment failed, continuing anyway..."
                }

              echo "✅ FIDO2 enrollment complete!"
            else
              echo "⚠️  No FIDO2 device found, password will be required on each boot"
            fi
          ''
        else
          ''
            echo "⚠️  Unknown backend type: ${cfg.backendType}"
          ''
      }

      # Clear passphrase from memory for security
      # (Note: Cannot completely prevent passphrase exposure in shell scripts,
      # but minimize the window)
      unset PASSPHRASE PASSPHRASE2 2>/dev/null || true

      # Mark encryption as complete
      # Note: /etc/crypttab is managed by NixOS via boot.initrd.luks.devices
      # No manual crypttab modification needed
      touch /mnt/.encryption-applied 2>/dev/null || true
      mount -o remount,rw /persist 2>/dev/null && touch "$STATE_FILE" || true
      sync

      echo ""
      echo "╔════════════════════════════════════════════════════════╗"
      echo "║              Encryption Setup Complete!               ║"
      echo "╚════════════════════════════════════════════════════════╝"
      echo ""
      echo "Your disk is now fully encrypted and protected."
      echo ""

      ${
        if config.ghaf.profiles.debug.enable then
          ''
            echo "Debug mode: System will reboot automatically in 5 seconds..."
            sleep 5
          ''
        else
          ''
            if [ -e /dev/tpmrm0 ]; then
              echo "On next boot:"
              echo "  • TPM will automatically unlock the disk"
              echo "  • You may be prompted for your PIN as additional security"
            else
              echo "On next boot:"
              echo "  • You will need to enter your password to unlock the disk"
            fi
            echo ""
            echo "Press Enter to reboot and complete setup..."
            read
          ''
      }

      echo "🔄 Rebooting system..."
      systemctl reboot
    '';
  };
in
{
  options.ghaf.storage.encryption = {
    deferred = mkEnableOption "Apply disk encryption on first boot instead of at image creation";
  };

  config = mkIf (cfg.enable && cfg.deferred) {
    # Ensure TPM support is enabled
    security.tpm2.enable = mkIf (cfg.backendType == "tpm2") true;

    # Install required tools
    environment.systemPackages = [
      pkgs.cryptsetup
      pkgs.lvm2
      pkgs.tpm2-tools
      pkgs.util-linux
      pkgs.parted
      pkgs.gptfdisk
    ];

    # First-boot encryption service
    systemd.services.first-boot-encrypt = {
      description = "First Boot Disk Encryption Setup";
      documentation = [ "https://github.com/tiiuae/ghaf" ];

      # Run early in boot, before most services
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "systemd-user-sessions.service"
      ];
      before = [
        "display-manager.service"
        "getty@tty1.service"
      ];

      # Only run if encryption hasn't been applied yet
      unitConfig = {
        ConditionPathExists = "!/persist/.encryption-applied";
        DefaultDependencies = false;
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe firstBootEncryptScript;
        RemainAfterExit = true;

        # Interactive service - needs TTY access
        StandardInput = "tty";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;

        # Run with elevated privileges
        User = "root";

        # Restart on failure
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # After encryption is applied, configure boot with LUKS.
    # NOTE: On first boot, the device is not yet encrypted, so initrd will
    # fail to unlock it. We use `nofail` in crypttabExtraOpts to allow boot
    # to continue. The first-boot-encrypt service will then apply encryption.
    # After the system reboots post-encryption, LUKS will be properly unlocked.
    boot.initrd.luks.devices.crypted = {
      device = lvmPartition;
      allowDiscards = true;
      bypassWorkqueues = true;

      # Crypttab options for TPM/FIDO2
      # Add 'x-systemd.device-timeout=5' to avoid long waits on first boot
      crypttabExtraOpts =
        if cfg.backendType == "tpm2" then
          [
            "tpm2-device=auto"
            "tpm2-measure-pcr=yes"
            "x-systemd.device-timeout=5"
            "nofail"
          ]
        else
          [
            "fido2-device=auto"
            "x-systemd.device-timeout=5"
            "nofail"
          ];
    };

    # Enable LVM support in initrd
    boot.initrd.services.lvm.enable = true;

    # Post-boot service to extend persist partition if needed
    systemd.services.extend-persist-postencrypt = {
      description = "Extend persist partition after encryption";
      after = [
        "local-fs.target"
        "first-boot-encrypt.service"
      ];
      wants = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig = {
        ConditionPathExists = [
          "/persist/.encryption-applied"
          "!/persist/.extend-persist-done"
        ];
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = getExe extendPersistScript;
      };
    };
  };
}
