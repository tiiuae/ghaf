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
  utils,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    getExe
    ;
  cfg = config.ghaf.storage.encryption;

  # Partition device to encrypt, set by the active partitioning module
  lvmPartition = cfg.partitionDevice;

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
      pkgs.kmod
      pkgs.pcsclite.lib
    ];
    text = ''
      LVM_PV="${lvmPartition}"
      # TODO: Need to assess the necessity of wiping the slot, as the
      # resize-partitions service currently relies on the password slot.
      WIPE_PASSWORD_SLOT=false

      # Wait for device to appear
      echo "Waiting for device $LVM_PV..."
      for _ in {1..30}; do
        if [ -e "$LVM_PV" ]; then
          echo "Device found."
          break
        fi
        sleep 1
      done

      # Check if device is already LUKS (state indicator)
      if cryptsetup isLuks "$LVM_PV"; then
        echo "Device already encrypted."
        if [ -e "/dev/mapper/crypted" ]; then
           echo "Device is unlocked. Skipping..."
           exit 0
        fi
        echo "Device is encrypted but NOT unlocked. Handing off unlock to systemd-cryptsetup..."

       # Ensure marker exists
        mkdir -p /run
        touch /run/cryptsetup-pre-checked

        # Start unlock asynchronously and return immediately.
        # This avoids keeping tty-force attached while TPM2 PIN is requested.
        echo "Starting systemd-cryptsetup@crypted (non-blocking)..."
        systemctl start --no-block systemd-cryptsetup@crypted || true
        exit 0
      fi

      # Check for installer/completion markers on the ESP partition.
        ESP_DEVICE=""
        for i in {1..10}; do
            ESP_DEVICE="$(lsblk -pn -o PATH,PARTLABEL | awk 'tolower($2) ~ /esp/ { print $1; exit }')"
            [ -n "$ESP_DEVICE" ] && break
            sleep 1
        done

        if [ -z "$ESP_DEVICE" ]; then
            echo "ESP partition not found, cannot check for markers. Skipping deferred encryption."
            exit 0
        fi

        mkdir -p /mnt/esp
        if ! mount "$ESP_DEVICE" /mnt/esp; then
          echo "Failed to mount ESP to check for markers. Skipping deferred encryption."
          exit 0
        fi

        # If it's not an installer-based boot, we also do nothing.
        if [ ! -f "/mnt/esp/.ghaf-installer-encrypt" ]; then
          echo "Not an installer-based installation (marker not found on ESP). Skipping deferred encryption."
          umount /mnt/esp
          exit 0
        fi

      # Stop Plymouth to show encryption progress
      if command -v plymouth >/dev/null 2>&1; then
        plymouth quit || true
        systemctl stop plymouth-quit-wait.service || true

        # Wait for TTY to properly reinitialize after Plymouth quits
        # This ensures the framebuffer console updates terminal dimensions
        # and text wrapping works correctly
        sleep 2
      fi

      # Ensure terminal is correctly configured for interaction
      export TERM=linux
      stty cols 256 2>/dev/null || true

      echo "+--------------------------------------------------------+"
      echo "|         First Boot - Disk Encryption Setup             |"
      echo "+--------------------------------------------------------+"
      echo ""
      echo "This system will now apply full disk encryption to protect"
      echo "your data. This process is irreversible and required for"
      echo "system security."
      echo ""

      ${
        if !cfg.interactiveSetup then
          ''
            # Automated mode: automatic encryption with default password as
            # systemd-cryptenroll cannot work with empty password
            echo "! Automated mode: Applying encryption automatically..."
            PASSPHRASE="ghaf"
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

            # Read passphrase securely using systemd-ask-password
            PASSPHRASE=""
            PASSPHRASE2="x"
            while [ "$PASSPHRASE" != "$PASSPHRASE2" ] || [ -z "$PASSPHRASE" ] || [ ''${#PASSPHRASE} -lt 4 ]; do
              # Use systemd-ask-password for robust TTY handling
              if ! PASSPHRASE=$(systemd-ask-password --timeout=0 "Enter encryption PIN/password (min 4 chars):"); then
                 echo "! Failed to read password"
                 sleep 2
                 continue
              fi
              echo ""

              if [ -z "$PASSPHRASE" ]; then
                echo "! Password cannot be empty"
                continue
              fi

              if [ ''${#PASSPHRASE} -lt 4 ]; then
                echo "! Password must be at least 4 characters"
                continue
              fi

              if ! PASSPHRASE2=$(systemd-ask-password --timeout=0 "Confirm PIN/password:"); then
                 echo "! Failed to read confirmation"
                 continue
              fi
              echo ""

              if [ "$PASSPHRASE" != "$PASSPHRASE2" ]; then
                echo "! Passwords don't match, please try again"
                echo ""
              fi
            done

            echo "! Password set successfully"
          ''
      }

      echo ""
      echo "! Preparing system for encryption..."

      # Ensure all filesystems are synced
      sync

      # Wait for any pending udev events
      udevadm settle

      # Shrink the PV to make space for LUKS header
      # We need to shrink it by at least 32M
      echo "! Resizing physical volume..."

      # Get current size in bytes
      PV_SIZE=$(blockdev --getsize64 "$LVM_PV")
      # Calculate new size (current - 32MB)
      NEW_SIZE=$((PV_SIZE - 32 * 1024 * 1024))

      echo "Current size: $PV_SIZE bytes"
      echo "New size:     $NEW_SIZE bytes"

      # Resize PV
      # We use --yes to confirm if prompted
      pvresize --setphysicalvolumesize "''${NEW_SIZE}B" --yes "$LVM_PV" || {
          echo "! Failed to resize PV, encryption might fail if no space for header"
      }

      # Deactivate all LVs to prepare for encryption
      echo "! Deactivating logical volumes..."

      # Show current state for debugging
      echo "DEBUG: Current LVM state:"
      lvs || true
      echo "DEBUG: Open devices:"
      dmsetup ls || true

      # Try to deactivate pool
      if ! vgchange -an pool; then
          echo "! Failed to deactivate pool, forcing..."

          # Debug: list /dev/mapper
          echo "DEBUG: /dev/mapper contents:"
          ls -la /dev/mapper/ || true

          # Try to force remove device mapper entries if vgchange failed
          # We iterate through dmsetup ls output to get exact names
          # Use || true for grep to avoid pipefail exit if no devices found
          dmsetup ls | { grep '^pool-' || true; } | awk '{print $1}' | while read -r dev; do
            [ -z "$dev" ] && continue
            echo "Forcing removal of device-mapper device: $dev"
            # Check open count
            dmsetup info -c "$dev" || true
            dmsetup remove -f "$dev" || true
          done

          # Try vgchange again
          vgchange -an pool || true
      fi

      sleep 1

      # Verify deactivation
      if dmsetup ls | grep -q "pool-"; then
          echo "! LVM volumes still active:"
          dmsetup ls
          exit 1
      fi

      # Unmount if mounted (shouldn't be at this stage but safety check)
      umount -f /persist 2>/dev/null || true
      swapoff -a 2>/dev/null || true

      echo ""
      echo "! Encrypting partition..."
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
      # Note: For empty passphrase (debug mode), we use printf to ensure a newline is sent
      printf '%s' "$PASSPHRASE" | cryptsetup reencrypt \
        --encrypt \
        --type luks2 \
        --reduce-device-size 32M \
        --resilience journal \
        --pbkdf argon2id \
        --pbkdf-memory 1048576 \
        --pbkdf-parallel 4 \
        --progress-frequency 5 \
        --verbose \
        "$LVM_PV" \
        --key-file=- || {
          echo "! Encryption failed!"
          exit 1
        }

      echo ""
      echo "! Encryption complete!"

      # Open the newly encrypted device
      echo "! Opening encrypted device..."
      printf '%s' "$PASSPHRASE" | cryptsetup open "$LVM_PV" crypted --key-file=- || {
        echo "! Failed to open encrypted device!"
        exit 1
      }

      # Activate LVM on the encrypted device for TPM enrollment
      echo "! Activating logical volumes..."
      vgchange -ay pool || {
        echo "! Failed to activate volume group!"
        exit 1
      }

      ${
        if cfg.backendType == "tpm2" then
          ''
            # Enroll TPM2 for automatic unlocking
            echo ""
            echo "! Enrolling TPM 2.0 for automatic unlock..."

            if [ -e /dev/tpmrm0 ]; then
              echo "!  TPM device found, checking readiness..."

              # Check if TPM is accessible
              if ! tpm2_getcap properties-fixed 2>/dev/null >/dev/null; then
                echo "!  Warning: TPM not accessible or not ready"
                echo "!  Skipping TPM enrollment, password will be required on each boot"
              else
                echo "!  TPM is ready, enrolling..."

                # Enroll TPM with optional PIN
                if PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                  --tpm2-device=auto \
                  --tpm2-pcrs=7 \
                  ${if cfg.interactiveSetup then "--tpm2-with-pin=yes" else "--tpm2-with-pin=no"} \
                  "$LVM_PV" 2>&1; then

                  # Add recovery key
                  echo "! Adding recovery key..."
                  PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                    --recovery \
                    "$LVM_PV" || {
                      echo "!  Recovery key enrollment failed"
                    }

                  # Remove the password slot only if TPM enrollment succeeded
                  if [ "$WIPE_PASSWORD_SLOT" = true ]; then
                    echo "!  Removing password slot..."
                    systemd-cryptenroll --wipe-slot=password "$LVM_PV" || {
                    echo "!  Could not remove password slot, it will remain available"
                   }
                   fi

                  echo "! TPM enrollment complete!"
                else
                  echo "!  TPM enrollment failed!"
                  echo "    Password slot will NOT be removed. You must use your password to unlock the disk."
                fi
              fi
            else
              echo "!  No TPM device found, password will be required on each boot"
            fi
          ''
        else if cfg.backendType == "fido2" then
          ''
            # Enroll FIDO2 device for unlocking
            echo ""
            echo "! Enrolling FIDO2 device for unlock..."

            if systemd-cryptenroll --fido2-device=list 2>/dev/null | grep -q '/dev'; then

               if systemctl is-active --quiet plymouth-start.service; then
                 plymouth quit || true
                 systemctl stop plymouth-quit-wait.service || true
                 sleep 2
                 echo 'Please confirm presence on security token'
               fi

              if PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                --fido2-device=auto \
                --fido2-with-user-presence=yes \
                --fido2-with-client-pin=yes \
                "$LVM_PV"; then

                # Add recovery key
                echo "! Adding recovery key..."
                PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                  --recovery \
                  "$LVM_PV" || {
                    echo "!  Recovery key enrollment failed"
                  }

                # Remove the password slot only if FIDO2 enrollment succeeded
                if [ "$WIPE_PASSWORD_SLOT" = true ]; then
                  echo "!  Removing password slot..."
                  systemd-cryptenroll --wipe-slot=password "$LVM_PV" || {
                    echo "!  Could not remove password slot, it will remain available"
                }
                fi

                echo "! FIDO2 enrollment complete!"
              else
                echo "!  FIDO2 enrollment failed!"
                echo "    Password slot will NOT be removed. You must use your password to unlock the disk."
              fi
            else
              echo "!  No FIDO2 device found, password will be required on each boot"
            fi
          ''
        else
          ''
            echo "!  Unknown backend type: ${cfg.backendType}"
          ''
      }

      # Clear passphrase from memory for security
      unset PASSPHRASE PASSPHRASE2 2>/dev/null || true

      # Write state file to prevent re-running on next boot
      echo "! Writing state file..."

      # Load filesystem modules
      echo "!  Loading filesystem modules..."
      echo "!  Available filesystems before loading:"
      cat /proc/filesystems | grep -E "btrfs|ext4" || echo "    (none found)"

      if modprobe btrfs 2>&1; then
        echo "!  btrfs module loaded"
      else
        echo "!  WARNING: Failed to load btrfs module"
      fi

      if modprobe ext4 2>&1; then
        echo "!  ext4 module loaded"
      else
        echo "!  WARNING: Failed to load ext4 module"
      fi

      # Wait for device to be ready
      echo "! Waiting for persist volume..."
      for i in {1..30}; do
        if [ -e /dev/mapper/pool-persist ]; then
          echo "!  Device found at iteration $i"
          break
        fi
        sleep 1
      done

      # Ensure udev has fully processed the device
      udevadm settle || true
      udevadm trigger --subsystem-match=block || true
      sleep 3

      # Check if device is really ready
      echo "!  Checking device readiness..."
      ls -la /dev/mapper/pool-persist || true
      blkid /dev/mapper/pool-persist || true

      # Try to mount and write state file with retries
      mkdir -p /tmp/persist
      MOUNT_SUCCESS=false

      for attempt in {1..5}; do
        echo "!  Mount attempt $attempt..."
        if mount -t btrfs /dev/mapper/pool-persist /tmp/persist 2>&1; then
          echo "!  Persist mounted successfully"
          MOUNT_SUCCESS=true
          break
        fi
        echo "!  Mount failed, waiting 2 seconds..."
        sleep 2
      done

      if [ "$MOUNT_SUCCESS" = true ]; then
        echo "!  Writing state marker..."
        if touch /tmp/persist/.encryption-applied; then
          echo "!  State file written successfully"
        else
          echo "!  Warning: Could not write state file"
        fi
        sync
        umount /tmp/persist || true
      else
        echo "!  ERROR: Failed to mount persist after 5 attempts"
        echo "!  The encryption will be attempted again on next boot"
        echo "!  Debug info:"
        dmsetup ls || true
        lvs || true
        lsmod | grep -E "btrfs|ext4" || true
        echo "!  Checking available filesystems:"
        cat /proc/filesystems || true

        ${
          if !cfg.interactiveSetup then
            ''
              echo ""
              echo "+--------------------------------------------------------+"
              echo "|              EMERGENCY DEBUG SHELL                      |"
              echo "+--------------------------------------------------------+"
              echo "Mount failed. Dropping to emergency shell for debugging."
              echo "Available commands: mount, lsmod, modprobe, blkid, lsblk"
              echo "Device: /dev/mapper/pool-persist"
              echo "Try: modprobe btrfs && mount -t btrfs /dev/mapper/pool-persist /tmp/persist"
              echo "Type 'exit' to continue boot (will retry encryption next boot)"
              echo ""
              /bin/sh
            ''
          else
            ""
        }
      fi

      # Deactivate LVM so system can boot cleanly
      echo "! Deactivating logical volumes for reboot..."
      vgchange -an pool || true
      cryptsetup close crypted || true

      echo ""
      echo "+--------------------------------------------------------+"
      echo "|              Encryption Setup Complete!                |"
      echo "+--------------------------------------------------------+"
      echo ""
      echo "Your disk is now fully encrypted and protected."
      echo "The system will reboot to complete the setup."
      echo ""

      # Remove the installer marker so we don't run again if this fails.
      rm -f /mnt/esp/.ghaf-installer-encrypt
      umount /mnt/esp
      rmdir /mnt/esp

      ${
        if !cfg.interactiveSetup then
          ''
            echo "Automated mode: Rebooting in 5 seconds..."
            sleep 5
          ''
        else
          ''
            if [ -e /dev/tpmrm0 ]; then
              echo "On next boot:"
              echo "  ! TPM will automatically unlock the disk"
              echo "  ! You may be prompted for your PIN as additional security"
            else
              echo "On next boot:"
              echo "  ! You will need to enter your password to unlock the disk"
            fi
            echo ""
            echo "Press Enter to reboot..."
            read -r
          ''
      }

      echo "! Rebooting system..."
      systemctl reboot
    '';
  };
in
{
  _file = ./deferred-disk-encryption.nix;

  options.ghaf.storage.encryption = {
    deferred = mkEnableOption "Apply disk encryption on first boot instead of at image creation";
  };

  config = mkIf (cfg.enable && cfg.deferred) {
    # Ensure TPM support is enabled
    security.tpm2.enable = mkIf (cfg.backendType == "tpm2") true;

    # Plymouth is enabled normally, but will be stopped during first-boot encryption
    # to ensure TTY access for password prompts. After encryption, Plymouth can
    # be used for subsequent boots including password entry for LUKS unlock.
    # leaving this here for future debugging purposes/reference.
    # boot.plymouth.enable = lib.mkForce false;

    # Install required tools
    environment.systemPackages = [
      pkgs.cryptsetup
      pkgs.lvm2
      pkgs.tpm2-tools
      pkgs.util-linux
      pkgs.parted
      pkgs.gptfdisk
    ];

    # Include required packages in initrd
    boot.initrd = {
      systemd = {
        storePaths = [
          pkgs.cryptsetup
          pkgs.lvm2
          pkgs.systemd
          pkgs.tpm2-tools
          pkgs.util-linux
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gawk
          pkgs.plymouth
          pkgs.btrfs-progs
          pkgs.e2fsprogs
          pkgs.kmod
          pkgs.pcsclite.lib
          firstBootEncryptScript
        ];

        services = {
          # First-boot encryption service (runs in initrd)
          first-boot-encrypt = {
            description = "First Boot Disk Encryption Setup (Initrd)";
            documentation = [ "https://github.com/tiiuae/ghaf" ];

            # Run in initrd BEFORE root is mounted
            wantedBy = [ "initrd.target" ];
            before = [
              "sysroot.mount"
              "initrd-root-fs.target"
            ];
            after = [
              "cryptsetup-pre.target"
              "systemd-cryptsetup@crypted.service"
            ];

            unitConfig = {
              DefaultDependencies = false;
            };

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;

              # Interactive service - needs TTY access
              StandardInput = "tty-force";
              StandardOutput = "journal+console";
              StandardError = "journal+console";

              # Disable restart - encryption only happens once
              Restart = "no";

              # Execute the encryption script
              ExecStart = getExe firstBootEncryptScript;
            };
          };

          # Override systemd-cryptsetup@crypted.service to add a condition
          # that checks if the device is actually LUKS before attempting unlock
          # We define the service manually to override the generator and add the condition
          "systemd-cryptsetup@crypted" = {
            description = "Cryptography Setup for crypted";
            documentation = [
              "man:crypttab(5)"
              "man:systemd-cryptsetup-generator(8)"
              "man:systemd-cryptsetup@.service(8)"
            ];

            unitConfig = {
              DefaultDependencies = false;
              Conflicts = "umount.target";
              Before = [
                "cryptsetup.target"
                "umount.target"
              ];
              After = [
                "cryptsetup-pre.target"
                "${utils.escapeSystemdPath lvmPartition}.device"
              ];
              BindsTo = [
                "dev-mapper-crypted.device"
                "${utils.escapeSystemdPath lvmPartition}.device"
              ];
              IgnoreOnIsolate = true;
              ConditionPathExists = "/run/cryptsetup-pre-checked";
            };

            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              TimeoutSec = 0;
              KeyringMode = "shared";
              OOMScoreAdjust = 500;
              ExecStart =
                let
                  # Replicate options from boot.initrd.luks.devices.crypted
                  # We hardcode standard options here to match what the generator would produce
                  options = [
                    "allow-discards"
                    "no-read-workqueue"
                    "no-write-workqueue"
                  ]
                  ++ config.boot.initrd.luks.devices.crypted.crypttabExtraOpts;
                  optionsStr = builtins.concatStringsSep "," options;
                in
                "${pkgs.systemd}/lib/systemd/systemd-cryptsetup attach crypted ${lvmPartition} - ${optionsStr}";
            };
          };

        };
      };

      # After encryption is applied, configure boot with LUKS.
      # On first boot, device is not encrypted yet. We use a systemd service
      # bound to cryptsetup-pre.target to skip LUKS unlock if device is not encrypted.
      luks.devices.crypted = {
        device = lvmPartition;
        allowDiscards = true;
        bypassWorkqueues = true;

        # Crypttab options for TPM/FIDO2
        crypttabExtraOpts =
          if cfg.backendType == "tpm2" then
            [
              "tpm2-device=auto"
              "tpm2-measure-pcr=yes"
            ]
          else
            [ "fido2-device=auto" ];
      };

      # Ensure necessary kernel modules and filesystem support in initrd
      # supportedFilesystems ensures the filesystem modules and tools are available
      supportedFilesystems = [
        "btrfs"
        "ext4"
        "vfat"
      ];

      availableKernelModules = [
        "dm-crypt"
        "dm-mod"
      ];

      kernelModules = [
        "dm-crypt"
        "dm-mod"
      ];

      # Enable LVM support in initrd
      services.lvm.enable = true;
    };
  };
}
