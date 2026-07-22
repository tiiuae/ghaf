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
    mkIf
    getExe
    ;
  cfg = config.ghaf.storage.encryption;

  # Partition device to encrypt, set by the active partitioning module
  lvmPartition = cfg.partitionDevice;

  firstBootEncryptScript = pkgs.writeShellApplication {
    name = "first-boot-encrypt";
    runtimeInputs = with pkgs; [
      # keep-sorted start
      btrfs-progs
      config.ghaf.security.tpm2.tools
      coreutils
      cryptsetup
      e2fsprogs
      gawk
      gnugrep
      gum
      kmod
      lvm2
      ncurses
      pcsclite.lib
      qrencode
      systemd
      util-linux
      # keep-sorted end
    ];
    text =
      let
        inherit (cfg) interactiveSetup backendType;
        tpm2WithPin = if interactiveSetup then "--tpm2-with-pin=yes" else "--tpm2-with-pin=no";
      in
      builtins.readFile ../../lib/gum-lib.sh
      + ''
        LVM_PV="${lvmPartition}"
        WIPE_PASSWORD_SLOT=false

        human_size() {
          local bytes="$1"
          local gib_tenths=$((bytes * 10 / 1024 / 1024 / 1024))
          if ((gib_tenths > 0)); then
            printf "%d.%d GiB (%d bytes)" "$((gib_tenths / 10))" "$((gib_tenths % 10))" "$bytes"
          else
            printf "%d MiB (%d bytes)" "$((bytes / 1024 / 1024))" "$bytes"
          fi
        }

        # ---------------------------------------------------------------------------
        # Wait for the LVM PV to appear
        # ---------------------------------------------------------------------------
        for _ in {1..30}; do [ -e "$LVM_PV" ] && break; sleep 1; done

        # ---------------------------------------------------------------------------
        # Fast-path: already encrypted
        # ---------------------------------------------------------------------------
        if cryptsetup isLuks "$LVM_PV"; then
          [ -e "/dev/mapper/crypted" ] && exit 0
          mkdir -p /run
          touch /run/cryptsetup-pre-checked
          systemctl start --no-block systemd-cryptsetup@crypted || true
          exit 0
        fi

        # ---------------------------------------------------------------------------
        # Check for installer marker on ESP
        # ---------------------------------------------------------------------------
        ESP_DEVICE=""
        for _ in {1..10}; do
          ESP_DEVICE="$(lsblk -pn -o PATH,PARTLABEL | awk 'tolower($2) ~ /esp/ { print $1; exit }')"
          [ -n "$ESP_DEVICE" ] && break
          sleep 1
        done

        if [ -z "$ESP_DEVICE" ]; then
          echo "ESP partition not found - cannot check for installer marker. Skipping deferred encryption."
          exit 0
        fi

        mkdir -p /mnt/esp
        if ! mount "$ESP_DEVICE" /mnt/esp; then
          echo "Failed to mount ESP - skipping deferred encryption."
          exit 0
        fi

        if [ ! -f "/mnt/esp/.ghaf-installer-encrypt" ]; then
          echo "Installer marker not found on ESP - skipping deferred encryption."
          umount /mnt/esp
          exit 0
        fi

        # ---------------------------------------------------------------------------
        # Stop Plymouth so GUM can own the framebuffer TTY
        #
        # This is the boundary: GUM is only safe to call below this block. Above it
        # plymouthd still owns the console, and GUM renders through a terminal
        # library that expects to own the TTY. The two deadlock, and since this
        # service is ordered Before=sysroot.mount, the boot hangs on the splash
        # forever. Use plain echo above this point.
        # ---------------------------------------------------------------------------
        if command -v plymouth >/dev/null 2>&1; then
          plymouth quit || true
          systemctl stop plymouth-quit-wait.service || true
          sleep 2
        fi

        clear
        show_header "First Boot - Disk Encryption Setup"
        echo ""
        show_section \
          "This system will now apply full-disk encryption to protect your data." \
          "This process is irreversible and required for system security."
        echo ""

        # ---------------------------------------------------------------------------
        # Obtain passphrase
        # ---------------------------------------------------------------------------
      ''
      + (
        if !interactiveSetup then
          ''
            show_warning "Automated mode: applying encryption automatically..."
            PASSPHRASE="ghaf"
          ''
        else
          ''
            countdown "Continuing in" 5
            clear
            show_header "First Boot - Disk Encryption Setup"
            echo ""
            show_info "You will be prompted to set an encryption PIN or password."
            show_section \
              "Requirements:" \
              "  - Minimum 4 characters" \
              "  - Cannot be empty"
            echo ""

            PASSPHRASE=""
            PASSPHRASE2="x"
            while [ "$PASSPHRASE" != "$PASSPHRASE2" ] \
                || [ -z "$PASSPHRASE" ] \
                || [ "''${#PASSPHRASE}" -lt 4 ]; do

              PASSPHRASE=$(prompt_password \
                "Set encryption password" \
                "Enter encryption PIN/password (min 4 chars)") || {
                  show_error "Failed to read password - retrying..."
                  sleep 1
                  continue
                }

              if [ -z "$PASSPHRASE" ]; then
                show_error "Password cannot be empty."
                continue
              fi

              if [ "''${#PASSPHRASE}" -lt 4 ]; then
                show_error "Password must be at least 4 characters."
                continue
              fi

              PASSPHRASE2=$(prompt_password \
                "Confirm password" \
                "Confirm your password") || {
                  show_error "Failed to read confirmation - retrying..."
                  PASSPHRASE2="x"
                  continue
                }

              if [ "$PASSPHRASE" != "$PASSPHRASE2" ]; then
                show_error "Passwords do not match - please try again."
                PASSPHRASE2="x"
              fi
            done

            show_success "Password set successfully." ""
          ''
      )
      + ''

        # ---------------------------------------------------------------------------
        # Prepare system
        # ---------------------------------------------------------------------------
        run_spin "Syncing filesystems..." sync
        run_spin "Settling udev events..." udevadm settle

        PV_SIZE=$(blockdev --getsize64 "$LVM_PV")
        NEW_SIZE=$((PV_SIZE - 32 * 1024 * 1024))

        show_section \
          "Physical volume: $(human_size "$PV_SIZE")" \
          "After shrink:    $(human_size "$NEW_SIZE")  (32 MiB reserved for LUKS header)"

        run_spin -q "Resizing physical volume..." \
          pvresize --setphysicalvolumesize "''${NEW_SIZE}B" --yes "$LVM_PV" || \
          show_warning "Failed to resize PV - encryption may fail if there is insufficient room for the LUKS header."

        if ! run_spin -q "Deactivating logical volumes..." vgchange -an pool; then
          show_warning "vgchange failed - attempting forced removal of device-mapper entries..."
          dmsetup ls | { grep '^pool-' || true; } | awk '{print $1}' | while read -r dev; do
            [ -z "$dev" ] && continue
            dmsetup remove -f "$dev" || true
          done
          vgchange -an pool || true
        fi

        run_spin -q "Waiting for device-mapper to settle..." sleep 1

        if dmsetup ls | grep -q "pool-"; then
          show_error "LVM volumes still active - cannot proceed."
          dmsetup ls
          exit 1
        fi

        run_spin -q "Unmounting persist..." umount -f /persist 2>/dev/null || true
        run_spin -q "Disabling swap..." swapoff -a 2>/dev/null || true

        countdown "Starting encryption in" 5

        # ---------------------------------------------------------------------------
        # Encrypt in-place
        # ---------------------------------------------------------------------------
        clear
        show_header "First Boot - Disk Encryption Setup"
        echo ""
        show_section \
          "Encrypting partition..." \
          "This will take several minutes depending on disk size." \
          "Please do not power off the system!"
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
          "$LVM_PV" \
          --key-file=- || {
            printf '\n'
            show_error "Encryption failed!"
            exit 1
          }

        printf '\n'
        show_success "Encryption complete!"

        printf '%s' "$PASSPHRASE" | cryptsetup open "$LVM_PV" crypted --key-file=- || {
          show_error "Failed to open encrypted device!"
          exit 1
        }
        show_success "Device opened."

        run_spin -q "Activating logical volumes..." vgchange -ay pool || {
          show_error "Failed to activate volume group!"
          exit 1
        }

        # ---------------------------------------------------------------------------
        # Enroll hardware unlock token
        # ---------------------------------------------------------------------------
        enroll_recovery_and_wipe() {
          show_info "Adding recovery key..."
          # systemd prints the key to stdout; capture it while discarding stderr
          RECOVERY_KEY="$(PASSWORD="$PASSPHRASE" systemd-cryptenroll --recovery-key "$LVM_PV" 2>/dev/null)"
          if [ -n "$RECOVERY_KEY" ]; then
            show_success "Recovery key enrolled successfully."
            RECOVERY_QR="$(echo -n "$RECOVERY_KEY" | qrencode -t ansiutf8 2>/dev/null)"
            show_section \
              "$(show_warning \
              "Please save this secret recovery key at a secure location." \
              "It may be used to regain access to the volume if the other credentials have been lost or forgotten.")" \
              "" \
              "$(show_info "$RECOVERY_KEY")" \
              "" \
              "$RECOVERY_QR"
            unset RECOVERY_KEY RECOVERY_QR 2>/dev/null || true
          else
            show_warning "Recovery key enrollment failed."
          fi
          if [ "$WIPE_PASSWORD_SLOT" = true ]; then
            run_spin -q "Removing password slot..." \
              systemd-cryptenroll --wipe-slot=password "$LVM_PV" || \
              show_warning "Could not remove password slot - it will remain available."
          fi
        }
      ''
      + (
        if backendType == "tpm2" then
          ''
            countdown "Continuing in" 5
            clear
            show_header "First Boot - Disk Encryption Setup"
            echo ""
            show_info "Enrolling TPM 2.0 for automatic unlock..."

            if [ -e /dev/tpmrm0 ]; then
              if ! tpm2_getcap properties-fixed 2>/dev/null >/dev/null; then
                show_warning "TPM not accessible - skipping TPM enrollment."
                show_warning "Password will be required on every boot."
              else
                show_success "TPM device is ready - enrolling..."

                if PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                    --tpm2-device=auto \
                    --tpm2-pcrs=7 \
                    ${tpm2WithPin} \
                    "$LVM_PV" 2>/dev/null; then
                  enroll_recovery_and_wipe
                  ${lib.optionalString interactiveSetup "wait_for_user"}
                  show_success "TPM enrollment complete!"
                else
                  show_error "TPM enrollment failed!"
                  show_warning "Password slot retained. You must use your password to unlock the disk."
                fi
              fi
            else
              show_warning "No TPM device found - password will be required on every boot."
            fi
          ''
        else if backendType == "fido2" then
          ''
            countdown "Continuing in" 5
            clear
            show_header "First Boot - Disk Encryption Setup"
            echo ""
            show_info "Enrolling FIDO2 device for unlock..."

            if systemd-cryptenroll --fido2-device=list 2>/dev/null | grep -q '/dev'; then
              show_info "Please confirm presence on your security token..."

              if PASSWORD="$PASSPHRASE" systemd-cryptenroll \
                  --fido2-device=auto \
                  --fido2-with-user-presence=yes \
                  --fido2-with-client-pin=yes \
                  "$LVM_PV" 2>/dev/null; then
                enroll_recovery_and_wipe
                ${lib.optionalString interactiveSetup "wait_for_user"}
                show_success "FIDO2 enrollment complete!"
              else
                show_error "FIDO2 enrollment failed!"
                show_warning "Password slot retained. You must use your password to unlock the disk."
              fi
            else
              show_warning "No FIDO2 device found - password will be required on every boot."
            fi
          ''
        else
          ''
            show_warning "Unknown backend type: ${backendType}"
          ''
      )
      + ''

        unset PASSPHRASE PASSPHRASE2 2>/dev/null || true

        # ---------------------------------------------------------------------------
        # Write completion marker on persist
        # ---------------------------------------------------------------------------
        if ! grep -qE '\bbtrfs$' /proc/filesystems; then
          run_spin -q "Loading btrfs module..." modprobe btrfs 2>/dev/null || show_warning "Failed to load btrfs module."
        fi

        run_spin "Waiting for persist volume..." \
          bash -c 'for _ in {1..30}; do [ -e /dev/mapper/pool-persist ] && exit 0; sleep 1; done'

        run_spin -q "Settling block devices..."        udevadm settle || true
        run_spin -q "Triggering block device events..." udevadm trigger --subsystem-match=block || true
        run_spin -q "Waiting for block devices..."     sleep 3

        mkdir -p /tmp/persist
        MOUNT_SUCCESS=false

        for attempt in {1..5}; do
          if mount -t btrfs /dev/mapper/pool-persist /tmp/persist 2>/dev/null; then
            MOUNT_SUCCESS=true
            break
          fi
          show_warning "Mount attempt $attempt failed - retrying..."
          sleep 2
        done

        if [ "$MOUNT_SUCCESS" = true ]; then
          touch /tmp/persist/.encryption-applied || show_warning "Could not write state file."
          sync
          umount /tmp/persist || true
          show_success "State file written."
        else
          show_error "Failed to mount persist after 5 attempts - encryption will be retried on next boot."
          dmsetup ls || true
          lvs       || true
      ''
      + (
        if !interactiveSetup then
          ''
            show_warning "Dropping to emergency shell. Type 'exit' to continue boot."
            /bin/sh
          ''
        else
          ""
      )
      + ''
        fi

        # ---------------------------------------------------------------------------
        # Cleanup and reboot
        # ---------------------------------------------------------------------------
        run_spin -q "Deactivating logical volumes..." vgchange -an pool || true
        cryptsetup close crypted || true

        rm -f /mnt/esp/.ghaf-installer-encrypt
        umount /mnt/esp
        rmdir  /mnt/esp

        countdown "Continuing in" 5
        clear
        show_header "Encryption Setup Complete!"
        echo ""
        show_success "Your disk is now fully encrypted and protected." ""
      ''
      + (
        if !interactiveSetup then
          ''
            countdown "Automated mode: rebooting in" 10
          ''
        else
          ''
            if [ -e /dev/tpmrm0 ]; then
              show_section \
                "On next boot:" \
                "  - TPM will automatically unlock the disk" \
                "  - You may be prompted for your PIN as additional security"
                echo ""
            else
              show_section \
                "On next boot:" \
                "  - You will need to enter your password to unlock the disk"
                echo ""
            fi
            until gum confirm \
              --affirmative="Reboot now" \
              --negative="Wait" \
              "Reboot to complete setup?"; do
              :
            done
          ''
      )
      + ''

        show_success "Rebooting system..."
        systemctl reboot
      '';
  };

in
{
  _file = ./deferred-disk-encryption.nix;

  # The ghaf.storage.encryption.deferred option is declared in
  # modules/common/security/disk-encryption.nix, which also reads it.

  config = mkIf (cfg.enable && cfg.deferred) {
    # Ensure TPM support is enabled
    security.tpm2.enable = mkIf (cfg.backendType == "tpm2") true;

    # Plymouth is enabled normally, but will be stopped during first-boot encryption
    # to ensure TTY access for password prompts. After encryption, Plymouth can
    # be used for subsequent boots including password entry for LUKS unlock.
    # leaving this here for future debugging purposes/reference.
    # boot.plymouth.enable = lib.mkForce false;

    # Install required tools
    environment.systemPackages = with pkgs; [
      config.ghaf.security.tpm2.tools
      cryptsetup
      gptfdisk
      lvm2
      parted
      util-linux
    ];

    # Include required packages in initrd
    boot.initrd = {
      systemd = {
        storePaths = with pkgs; [
          # keep-sorted start
          btrfs-progs
          config.ghaf.security.tpm2.tools
          coreutils
          cryptsetup
          e2fsprogs
          firstBootEncryptScript
          gawk
          gnugrep
          gum
          kmod
          lvm2
          ncurses
          pcsclite.lib
          plymouth
          qrencode
          systemd
          util-linux
          # keep-sorted end
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

              # Interactive service - needs direct TTY access.
              # "tty" (not "journal+console") is required so GUM's ANSI
              # escape sequences reach the terminal unmodified; the journal
              # path prepends timestamps and service metadata to every line
              # which breaks GUM rendering entirely.
              StandardInput = "tty-force";
              StandardOutput = "tty";
              StandardError = "tty";

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
                  # Derive the options from boot.initrd.luks.devices.crypted so this
                  # manual first-boot unit can never drift from the generator settings.
                  luksDev = config.boot.initrd.luks.devices.crypted;
                  options =
                    lib.optional luksDev.allowDiscards "allow-discards"
                    ++ lib.optionals luksDev.bypassWorkqueues [
                      "no-read-workqueue"
                      "no-write-workqueue"
                    ]
                    ++ luksDev.crypttabExtraOpts;
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
