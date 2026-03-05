# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Two-phase initrd flash for Ghaf on NVIDIA Jetson Orin.
#
# Overrides upstream jetpack-nixos flashInitrd and initrdFlashScript.
#
# Phase 1 (device-side, small initrd ~300 MB):
#   - Boot via RCM, flash firmware to QSPI + eMMC boot blocks
#   - Reconfigure USB gadget: add mass_storage function exposing eMMC
#   - Signal "EMMC_READY" on serial, wait for host to write images
#
# Phase 2 (host-side, via USB mass storage):
#   - Detect eMMC as USB mass storage block device
#   - Create GPT (ESP + root) with sgdisk, write compressed images with dd
#   - Signal "IMAGES_DONE" on serial, device reboots
#

{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  jetpackCfg = config.hardware.nvidia-jetpack;

  inherit (config.system.build) ghafFlashImages;

  # x86_64 package set used for building the host-side flash script.
  # NVIDIA's flash tools are x86_64-only prebuilt binaries.
  inherit (jetpackCfg) flasherPkgs;

  # ---------------------------------------------------------------------------
  # Device-side: flash initrd
  # ---------------------------------------------------------------------------

  spiModules =
    if lib.versions.majorMinor config.system.build.kernel.version == "5.10" then
      [
        "qspi_mtd"
        "spi_tegra210_qspi"
        "at24"
        "spi_nor"
      ]
    else
      [
        "mtdblock"
        "spi_tegra210_quad"
      ];

  usbModules =
    if lib.versions.majorMinor config.system.build.kernel.version == "5.10" then
      [ ]
    else
      [
        "libcomposite"
        "udc-core"
        "tegra-xudc"
        "xhci-tegra"
        "u_serial"
        "usb_f_acm"
        "usb_f_mass_storage"
        "configfs"
        "usb_common"
      ];

  modules = spiModules ++ usbModules ++ jetpackCfg.flashScriptOverrides.additionalInitrdFlashModules;

  modulesClosure = pkgs.makeModulesClosure {
    rootModules = modules;
    kernel = config.system.modulesTree;
    inherit (config.hardware) firmware;
    allowMissing = false;
  };

  manufacturer = "NixOS";
  product = "serial";
  serialnumber = "0";
  # Use a prefix (not fixed -if00) because interface index can change in composite gadget
  serialPortPrefix = "usb-${manufacturer}_${product}_${serialnumber}-if";

  ghafFlashInit = pkgs.writeScript "init" ''
    #!${pkgs.pkgsStatic.busybox}/bin/sh
    export PATH=${pkgs.pkgsStatic.busybox}/bin
    mkdir -p /proc /dev /sys
    mount -t proc proc -o nosuid,nodev,noexec /proc
    mount -t devtmpfs none -o nosuid /dev
    mount -t sysfs sysfs -o nosuid,nodev,noexec /sys
    ln -s /proc/self/fd /dev/

    for mod in ${toString modules}; do
      modprobe -v "$mod" || true
    done

    mount -t configfs none /sys/kernel/config || true
    if [ -e /sys/kernel/config/usb_gadget ] ; then
      gadget=/sys/kernel/config/usb_gadget/g.1
      mkdir -p "$gadget"

      echo 0x1d6b >"$gadget/idVendor"
      echo 0x0104 >"$gadget/idProduct"

      mkdir -p "$gadget/strings/0x409"
      echo ${manufacturer} >"$gadget/strings/0x409/manufacturer"
      echo ${product} >"$gadget/strings/0x409/product"
      echo ${serialnumber} >"$gadget/strings/0x409/serialnumber"

      mkdir -p "$gadget/configs/c.1"
      mkdir -p "$gadget/configs/c.1/strings/0x409"
      echo "Flash config" >"$gadget/configs/c.1/strings/0x409/configuration"

      # Create ACM for Phase 1 (serial only)
      mkdir -p "$gadget/functions/acm.usb0"
      ln -s "$gadget/functions/acm.usb0" "$gadget/configs/c.1/"

      if [ -w /sys/bus/usb/devices/usb2/power/control ] ; then
        echo on >/sys/bus/usb/devices/usb2/power/control
      fi

      # Wait for UDC to appear
      while [ -z "$(ls /sys/class/udc 2>/dev/null | head -n 1)" ] ; do
        echo "Waiting for /sys/class/udc/*"
        sleep 1
      done
      UDC_NAME="$(ls /sys/class/udc | head -n 1)"

      # Switch to peripheral/device role before binding
      if [ -d /sys/class/usb_role ]; then
        for role in /sys/class/usb_role/*/role; do
          [ -w "$role" ] && echo device > "$role" 2>/dev/null || true
        done
      fi
      sleep 1

      # Bind with simple retry (avoids transient EBUSY)
      if ! echo "$UDC_NAME" >"$gadget/UDC" 2>/dev/null; then
        echo "UDC busy, retrying bind..."
        sleep 1
        echo "$UDC_NAME" >"$gadget/UDC" 2>/dev/null || true
      fi

      sleep 1
      mdev -s

      ttyGS="/dev/ttyGS$(cat "$gadget/functions/acm.usb0/port_num")"
    else
      echo "ERROR: USB gadget configfs not available"
      echo "Cannot establish serial communication with host."
      ${
        if cfg.flashScriptOverrides.onlyQSPI then
          ''
            echo "QSPI-only mode: continuing without serial."
          ''
        else
          ''
            echo "Full flash requires USB gadget for mass storage. Rebooting."
            sleep 10
            reboot -f
          ''
      }
    fi

    echo "============================================================"
    echo "Ghaf initrd flash for NVIDIA Jetson Orin"
    echo "============================================================"

    # Phase 1: Flash firmware
    # Note: stdout goes to console only (NOT tee'd to serial) to avoid
    # filling the USB serial TX buffer and blocking protocol messages.
    echo "Phase 1: Flashing platform firmware..."
    if ! ${lib.getExe pkgs.nvidia-jetpack.flashFromDevice} ${pkgs.nvidia-jetpack.signedFirmware}; then
      echo "Flashing platform firmware unsuccessful."
      [ -e "$ttyGS" ] && echo "Flashing platform firmware unsuccessful." > "$ttyGS"
      ${lib.optionalString (jetpackCfg.firmware.secureBoot.pkcFile == null) ''
        echo "Entering console"
        exec ${pkgs.pkgsStatic.busybox}/bin/sh
      ''}
      sleep 30
      reboot -f
    fi
    echo "FIRMWARE_DONE"
    [ -e "$ttyGS" ] && echo "FIRMWARE_DONE" > "$ttyGS"

    ${
      if cfg.flashScriptOverrides.onlyQSPI then
        ''
          echo "============================================================"
          echo "Flashing platform firmware successful"
          echo "============================================================"
          [ -e "$ttyGS" ] && echo "Flashing platform firmware successful" > "$ttyGS"
          sync
          reboot -f
        ''
      else
        ''
          # Phase 2: Expose eMMC as USB mass storage
          echo "Phase 2: Reconfiguring USB gadget for mass storage..."

          # --- Proper UDC unbind + cleanup for Jetson Orin ---

          # Hard unbind ("" is not enough on kernel 6.6)
          if [ -e "$gadget/UDC" ]; then
            echo "none" > "$gadget/UDC" 2>/dev/null || true
          fi

          # Remove ALL symlinks under configs/c.1
          find "$gadget/configs/c.1" -maxdepth 1 -type l -exec rm {} \;

          # Recreate functions
          mkdir -p "$gadget/functions/acm.usb0"
          mkdir -p "$gadget/functions/mass_storage.usb0"

          # Wait up to 30s for eMMC to be present before assigning LUN
          for t in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
            [ -b /dev/mmcblk0 ] && break
            sleep 1
          done

          # Detect the real eMMC user area device
          EMMC_USER=""
          for dev in /sys/block/mmcblk*/size; do
              sz=$(cat "$dev" 2>/dev/null || echo 0)
              if [ "$sz" -gt 100000 ]; then
                  base=$(echo "$dev" | sed 's#/size$##')
                  EMMC_USER="/dev/$(basename $base)"
              fi
          done

          # Fallback for early initrd:
          [ -e "$EMMC_USER" ] || EMMC_USER="/dev/mmcblk0"

          echo "$EMMC_USER" > "$gadget/functions/mass_storage.usb0/lun.0/file"
          echo 0 > "$gadget/functions/mass_storage.usb0/lun.0/ro"

          # Link ACM FIRST
          ln -s "$gadget/functions/acm.usb0"          "$gadget/configs/c.1/"
          ln -s "$gadget/functions/mass_storage.usb0" "$gadget/configs/c.1/"

          # Correct role switch (must be BEFORE binding)
          for r in /sys/class/usb_role/*/role; do
            echo device > "$r" 2>/dev/null || true
          done
          sleep 1

          # Retry UDC bind with shorter delay (T234 timing)
          UDC_NAME="$(ls /sys/class/udc | head -n1)"
          for i in 1 2 3 4 5; do
            echo "$UDC_NAME" > "$gadget/UDC" 2>/dev/null && break
            sleep 0.2
          done

          sleep 1
          mdev -s

          # --- WAIT FOR ACM ENDPOINTS TO BE FULLY ENABLED ---
          # ttyGS node appears early, but ACM endpoints (EP5, EP3, EP2) become active later.
          # Without this wait, device never receives IMAGES_DONE.
          echo "Waiting for ACM endpoints to become active..."
          for n in $(seq 1 600); do
            if dmesg | grep -q "EP 5 (type: intr, dir: in) enabled"; then
              echo "ACM endpoints active."
              break
            fi
            sleep 1
          done

          # Re-read serial device path after gadget reconnect
          ttyGS="/dev/ttyGS$(cat "$gadget/functions/acm.usb0/port_num")"

          # 1) Wait until the tty node actually appears (after UDC rebind)
          for n in 1 2 3 4 5 6 7 8 9 10; do
            [ -e "$ttyGS" ] && break
            sleep 1
          done

          # 2) Wait until the tty is writable (avoid 'Resource busy' on first write)
          for n in 1 2 3 4 5; do
            echo "" > "$ttyGS" 2>/dev/null && break
            sleep 1
          done

          # >>> ADD THIS: put the device-side serial in raw, no-echo mode <<<
          stty -F "$ttyGS" 115200 raw -echo -echoe -echok -icanon -opost -isig -ixon -ixoff min 0 time 1 2>/dev/null || true

          # Drain stale bytes produced during gadget rebind so we do NOT miss host's IMAGES_DONE
          dd if="$ttyGS" of=/dev/null bs=1 count=1024 2>/dev/null || true

          # --- Permenant R/W fd open: prevents first line loss after tegra-xudc rebind ---
          echo "Opening persistent fd to $ttyGS..."
          opened=0
          for n in 1 2 3 4 5; do
            exec 3<> "$ttyGS" && opened=1 && break
            sleep 1
          done
          [ "$opened" -eq 1 ] || { echo "ERROR: cannot open $ttyGS"; reboot -f; }

          # Proactively send EMMC_READY several times to survive host open races
          for i in 1 2 3 4 5; do
            echo "EMMC_READY"
            printf 'EMMC_READY\n' >&3 2>/dev/null || true
            sleep 1
          done

          # Wait for host to finish writing images (timeout: 30 min)
          echo "Serial ready on $ttyGS; entering IMAGES_DONE wait loop..."
          echo "Waiting for host to write OS images..."
          wait_secs=0
          got_done=0
          resend_tick=0
          while [ $wait_secs -lt 1800 ]; do
          # FD-3 liveness: tty reset olduysa yeniden aç
            if ! : >&3 2>/dev/null; then
              exec 3<> "$ttyGS" 2>/dev/null || true
              # line discipline toparlansın
              usleep 100000 2>/dev/null || sleep 0.1
            fi
            # Periodically re-emit EMMC_READY while waiting (every 5s)
            resend_tick=$((resend_tick + 1))
            if [ $((resend_tick % 5)) -eq 0 ]; then
              printf 'EMMC_READY\n' >&3 2>/dev/null || true
            fi

            if IFS= read -r -t 1 line <&3 2>/dev/null; then
              line="''${line%$'\r'}"
              echo "  [host] $line"
              case "$line" in
                IMAGES_DONE*)
                  got_done=1
                  printf 'IMAGES_ACK\n' >&3 2>/dev/null || true
                  usleep 100000 2>/dev/null || sleep 0.1
                  printf 'IMAGES_ACK\n' >&3 2>/dev/null || true
                  break
                  ;;
                # Host probe to trigger a fresh EMMC_READY if it missed earlier emits
                EMMC_QUERY*)
                  printf 'EMMC_READY\n' >&3 2>/dev/null || true
                  ;;
              esac
            fi

            wait_secs=$((wait_secs + 1))
          done

          if [ $got_done -eq 0 ]; then
            echo "ERROR: Timed out waiting for host (30 min). Rebooting."
          else
            echo "============================================================"
            echo "Flashing platform firmware successful"
            echo "============================================================"
            printf 'Flashing platform firmware successful\n' >&3 2>/dev/null || true
          fi
          sync
          sleep 2
          reboot -f
        ''
    }
  '';

  ghafFlashInitrd =
    (pkgs.makeInitrd {
      contents = [
        {
          object = ghafFlashInit;
          symlink = "/init";
        }
        {
          object = modulesClosure;
          symlink = "/lib";
          suffix = "/lib";
        }
      ];
    }).overrideAttrs
      (prev: {
        passthru = prev.passthru // {
          inherit manufacturer product serialnumber;
        };
      });

  # ---------------------------------------------------------------------------
  # Host-side: DTS overlay to force USB peripheral mode
  # Replicated from upstream initrdflash-script.nix
  # ---------------------------------------------------------------------------

  inherit (pkgs.nvidia-jetpack) l4tMajorMinorPatchVersion;
  jetpackAtLeast = lib.versionAtLeast jetpackCfg.majorVersion;

  forceXusbPeripheralDts =
    let
      overridePaths = {
        "38" = {
          thor = {
            xudcPadctlPath = "bus@0/padctl@a808680000";
            xudcPath = "bus@0/usb@a808670000";
          };
        };
        "36" = {
          orin = {
            xudcPadctlPath = "bus@0/padctl@3520000";
            xudcPath = "bus@0/usb@3550000";
          };
        };
        "35" = {
          orin = {
            xudcPadctlPath = "xusb_padctl@3520000";
            xudcPath = "xudc@3550000";
          };
          xavier = {
            xudcPadctlPath = "xusb_padctl@3520000";
            xudcPath = "xudc@3550000";
          };
        };
      };
      l4tMajor = lib.versions.major l4tMajorMinorPatchVersion;
      soc = builtins.elemAt (lib.strings.split "-" jetpackCfg.som) 0;
      inherit (overridePaths.${l4tMajor}.${soc}) xudcPadctlPath xudcPath;
    in
    flasherPkgs.writeText "force-xusb-peripheral.dts" ''
      /dts-v1/;

      / {
        fragment@0 {
          target-path = "/${xudcPadctlPath}/ports/usb2-0";

          board_config {
            sw-modules = "kernel", "uefi";
          };

          __overlay__ {
            mode = "peripheral";
            usb-role-switch;
            connector {
              compatible = "usb-b-connector", "gpio-usb-b-connector";
              label = "usb-recovery";
              cable-connected-on-boot = <2>;
            };
          };
        };

        fragment@1 {
          target-path = "/${xudcPath}";

          board_config {
            sw-modules = "kernel", "uefi";
          };

          __overlay__ {
            status = "okay";
          };
        };
      };
    '';

  forceXusbPeripheralDtbo = flasherPkgs.deviceTree.compileDTS {
    name = "force-xusb-peripheral.dtbo";
    dtsFile = forceXusbPeripheralDts;
  };

  # ---------------------------------------------------------------------------
  # Host-side: RCM boot script text
  #
  # Replicates upstream mkRcmBootScript from device-pkgs/default.nix.
  # Uses mkFlashScript with x86_64 flash-tools to produce shell commands
  # that boot the device via RCM with our custom flash initrd.
  # ---------------------------------------------------------------------------

  rcmScript = pkgs.nvidia-jetpack.mkFlashScript flasherPkgs.nvidia-jetpack.flash-tools {
    preFlashCommands = ''
      cp ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} kernel/Image
      cp ${ghafFlashInitrd}/initrd bootloader/l4t_initrd.img

      export CMDLINE="${
        lib.concatStringsSep " " (
          [
            "sdhci_tegra.en_boot_part_access=1"
          ]
          ++ jetpackCfg.console.args
        )
      }"
      export INITRD_IN_BOOTIMG="yes"
    ''
    + lib.optionalString (jetpackCfg.firmware.secureBoot.pkcFile != null) ''
      (
        ${jetpackCfg.firmware.secureBoot.preSignCommands flasherPkgs.buildPackages}
        bash ./l4t_uefi_sign_image.sh --image ./kernel/Image --cert ${jetpackCfg.firmware.uefi.secureBoot.signer.cert} --key ${jetpackCfg.firmware.uefi.secureBoot.signer.key} --mode nosplit
      )
    '';

    flashArgs = [
      "--rcm-boot"
    ]
    ++ lib.optional (jetpackAtLeast "7") "-r"
    ++ lib.optional (jetpackCfg.firmware.secureBoot.pkcFile != null) "--no-flash"
    ++ jetpackCfg.flashScriptOverrides.flashArgs;

    postFlashCommands =
      lib.optionalString (jetpackCfg.firmware.secureBoot.pkcFile != null) ''
        (
          cd bootloader
          ${jetpackCfg.firmware.secureBoot.preSignCommands flasherPkgs.buildPackages}
          bash ../l4t_uefi_sign_image.sh --image boot.img --cert ${jetpackCfg.firmware.uefi.secureBoot.signer.cert} --key ${jetpackCfg.firmware.uefi.secureBoot.signer.key} --mode append
        )
      ''
      +
        lib.optionalString
          (
            builtins.length jetpackCfg.firmware.variants != 1 && jetpackCfg.firmware.secureBoot.pkcFile != null
          )
          ''
            (
              echo "Flashing device now"
              cd bootloader; bash ./flashcmd.txt
            )
          '';

    additionalDtbOverlays =
      (lib.filter (
        path: (path.name or "") != "DefaultBootOrder.dtbo"
      ) jetpackCfg.flashScriptOverrides.additionalDtbOverlays)
      ++ [ forceXusbPeripheralDtbo ];
  };

  # ---------------------------------------------------------------------------
  # Host-side: complete flash script
  # ---------------------------------------------------------------------------

  ghafFlashScript =
    (flasherPkgs.writeShellApplication {
      name = "initrd-flash-${config.networking.hostName}";
      runtimeInputs = with flasherPkgs; [
        gptfdisk
        zstd
        util-linux
        coreutils
      ];
      text = ''
        # --- Phase 1: RCM boot ---
        ${rcmScript}

        echo
        echo "Device is booting initrd flash environment..."

        # We cannot pin -if00 because after rebind the interface index can change.
        SERIAL_PREFIX="/dev/serial/by-id/${serialPortPrefix}"

        find_serial() {
          local timeout="$1"
          local end=$((SECONDS + timeout))
          while [ $SECONDS -lt $end ]; do
            for dev in "$SERIAL_PREFIX"*; do
              [ -e "$dev" ] && { echo "$dev"; return 0; }
            done
            sleep 1
          done
          return 1
        }

        wait_for_message() {
          local port="$1"
          local msg="$2"
          local timeout="$3"
          local end=$((SECONDS + timeout))
          echo "Waiting for message: $msg (timeout: ''${timeout}s)"

          # Open port once (FD 9), do not reopen or close again
          exec 9< "$port" 2>/dev/null || true

          while [ $SECONDS -lt $end ]; do
            # If port is lost reopen
            if [ ! -e "$port" ]; then
              sleep 1
              exec 9< "$port" 2>/dev/null || true
              continue
            fi

            # Read from FD 9 (CR/LF normalize)
            if IFS= read -r -t 1 -u 9 line 2>/dev/null; then
              line="''${line%$'\r'}"
              echo "  [device] $line"
              case "$line" in
                *"$msg"*) exec 9<&- 2>/dev/null || true; return 0 ;;
                *"unsuccessful"*)
                  echo "ERROR: Device reported failure"
                  exec 9<&- 2>/dev/null || true
                  return 1
                  ;;
              esac
            fi
          done

          echo "ERROR: Timed out waiting for: $msg"
          exec 9<&- 2>/dev/null || true
          return 1
        }

        # Wait for either EMMC_READY on serial, or successful USB mass-storage detection.
        wait_for_emmc_ready_or_msd() {
          local port="$1"
          local timeout="$2"
          local end=$((SECONDS + timeout))

          # Prompt the device to (re)send EMMC_READY in case we missed it
          echo "EMMC_QUERY" > "$port" 2>/dev/null || true

          while [ $SECONDS -lt $end ]; do
            # Try reading serial, non-blocking 1s
            if [ -e "$port" ] && IFS= read -r -t 1 line < "$port" 2>/dev/null; then
              echo "  [device] $line"
              case "$line" in
                *"EMMC_READY"*) return 0 ;;
              esac
            fi

            # In parallel, try to detect the mass storage device; if found, we treat it as ready.
            EMMC_DEV=$(detect_mass_storage 1) && {
              echo "Mass storage detected at: $EMMC_DEV"
              return 0
            }
          done

          return 1
        }

        detect_mass_storage() {
          local timeout="$1"
          local end=$((SECONDS + timeout))
          # Match by USB gadget VID:PID (1d6b:0104 = Linux Foundation Multifunction Composite Gadget)
          # to avoid accidentally selecting other USB storage devices on the host.
          local target_vid="1d6b"
          local target_pid="0104"
          echo "Scanning for USB mass storage device (VID=$target_vid PID=$target_pid)..." >&2
          while [ $SECONDS -lt $end ]; do
            for dev in /sys/block/sd*; do
              [ -e "$dev" ] || continue
              local devpath
              devpath=$(readlink -f "$dev/device" 2>/dev/null) || continue
              echo "$devpath" | grep -q usb || continue
              # Walk up to find the USB device with idVendor/idProduct
              local usbdev="$devpath"
              while [ -n "$usbdev" ] && [ "$usbdev" != "/" ]; do
                if [ -f "$usbdev/idVendor" ] && [ -f "$usbdev/idProduct" ]; then
                  local vid pid
                  vid=$(cat "$usbdev/idVendor")
                  pid=$(cat "$usbdev/idProduct")
                  if [ "$vid" = "$target_vid" ] && [ "$pid" = "$target_pid" ]; then
                    echo "/dev/$(basename "$dev")"
                    return 0
                  fi
                  break
                fi
                usbdev=$(dirname "$usbdev")
              done
            done
            sleep 1
          done
          echo "ERROR: No USB mass storage device with VID=$target_vid PID=$target_pid detected within ''${timeout}s" >&2
          return 1
        }

        # Wait for device serial port to appear (Phase 1)
        SERIAL_PORT="$(find_serial 240)" || {
          echo "ERROR: serial port did not appear"; exit 1; }

        # Configure serial port for raw I/O
        stty -F "$SERIAL_PORT" 115200 raw -echo -echoe -echok min 0 time 1

        # Monitor firmware flash progress
        wait_for_message "$SERIAL_PORT" "FIRMWARE_DONE" 900

        ${
          if cfg.flashScriptOverrides.onlyQSPI then
            ''
              # QSPI-only mode: just wait for the final success message
              wait_for_message "$SERIAL_PORT" "Flashing platform firmware successful" 30
              echo "QSPI flash complete. Device is rebooting."
            ''
          else
            ''
              # --- Phase 2: Write OS images via USB mass storage ---

              # On failure, do NOT send IMAGES_DONE — let the device timeout and
              # reboot safely rather than potentially booting a corrupt rootfs.

              phase2_cleanup() {
                echo "ERROR: Host-side failure during Phase 2."
                echo "Device will timeout and reboot in ~30 minutes."
                echo "You can re-run this script after putting the device back in RCM mode."
              }
              trap 'phase2_cleanup' EXIT

              # Serial will disconnect briefly during gadget reconfiguration
              echo "Waiting for device to reconfigure USB (serial + mass storage)..."
              sleep 3

              # Re-discover serial by prefix (interface index may change)
              SERIAL_PORT="$(find_serial 600)" || {
                echo "ERROR: serial port did not reappear after rebind"; exit 1; }

              # Reconfigure serial after reconnect
              stty -F "$SERIAL_PORT" 115200 raw -echo -echoe -echok min 0 time 1

              # Drain buffers
              dd if="$SERIAL_PORT" of=/dev/null bs=1 count=1024 2>/dev/null || true

              wait_for_emmc_ready_or_msd "$SERIAL_PORT" 600 || {
                echo "ERROR: Timed out waiting for EMMC_READY and no mass storage detected"; exit 1;
              }

              # Detect eMMC mass storage device
              EMMC_DEV="$(detect_mass_storage 30)" || {
                echo "ERROR: could not find eMMC mass storage device"; exit 1; }
              echo "Found eMMC at: $EMMC_DEV"

              # Unmount any auto-mounted partitions (desktop environments may auto-mount)
              for part in "$EMMC_DEV"*; do
                if mountpoint -q "$(findmnt -n -o TARGET "$part" 2>/dev/null)" 2>/dev/null; then
                  echo "Unmounting auto-mounted $part..."
                  umount "$part" 2>/dev/null || umount -l "$part" 2>/dev/null || true
                fi
              done

              echo "Creating GPT partition table on $EMMC_DEV..."
              sgdisk --zap-all "$EMMC_DEV"
              sgdisk --new=1:0:+256M --typecode=1:EF00 --change-name=1:FIRMWARE "$EMMC_DEV"
              sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:NIXOS_ROOT "$EMMC_DEV"
              sgdisk --print "$EMMC_DEV"

              # The kernel often still uses the old partition table here → do NOT abort
              blockdev --rereadpt "$EMMC_DEV" || true

              # Force rescan (this is the correct fallback on USB mass-storage gadgets)
              partprobe "$EMMC_DEV" 2>/dev/null || true

              # Let udev catch up
              udevadm settle 2>/dev/null || true

              # Wait for partitions to appear (mandatory!)
              for _ in $(seq 1 40); do
                if [ -e "''${EMMC_DEV}1" ] && [ -e "''${EMMC_DEV}2" ]; then
                  break
                fi
                sleep 0.25
              done

              FLASH_IMAGES="${ghafFlashImages}"
              echo "Writing ESP image to ''${EMMC_DEV}1"
              zstd -d "$FLASH_IMAGES/esp.img.zst" --stdout | dd of="''${EMMC_DEV}1" bs=4M status=progress
              echo "Writing ESP image to ''${EMMC_DEV}2"
              zstd -d "$FLASH_IMAGES/root.img.zst" --stdout | dd of="''${EMMC_DEV}2" bs=4M status=progress
              sync

              # Give the device a moment to reopen ACM after long I/O
              sleep 1

              # Re-discover serial in case the by-id symlink changed during the long writes
              SERIAL_PORT="$(find_serial 600)" || {
                echo "ERROR: serial port disappeared after writes"; exit 1; }
              stty -F "$SERIAL_PORT" 115200 raw -echo -echoe -echok min 0 time 1

              # Empty the lines that may come from the device for a clean start
              dd if="$SERIAL_PORT" of=/dev/null bs=1 count=1024 2>/dev/null || true

              # Signal completion to device with retries; accept ACK or final banner
              trap - EXIT
              for _ in $(seq 1 60); do   # ~5–6 minutes total (60 * (1 + waits))
                printf 'IMAGES_DONE\n' > "$SERIAL_PORT" 2>/dev/null || true

                # Give device time to answer — ACM is flaky right after MSC heavy writes
                if wait_for_message "$SERIAL_PORT" "IMAGES_ACK" 15; then
                  # Got ACK — now wait up to 60s for banner (device may sync/reboot prep)
                  if wait_for_message "$SERIAL_PORT" "Flashing platform firmware successful" 60 \
                  || wait_for_message "$SERIAL_PORT" "Finished flashing device" 60; then
                    echo "Flash complete. Device is rebooting."
                    exit 0
                  fi
                else
                  # No ACK yet, but accept final banner directly (older initrd / racey timing)
                  if wait_for_message "$SERIAL_PORT" "Flashing platform firmware successful" 10 \
                  || wait_for_message "$SERIAL_PORT" "Finished flashing device" 10; then
                    echo "Flash complete. Device is rebooting."
                    exit 0
                  fi
                fi

                sleep 1
              done

              echo "ERROR: Device did not confirm completion in time."
              exit 1
            ''
        }
      '';
      meta.platforms = [ "x86_64-linux" ];
    }).overrideAttrs
      (_prev: {
        # Some nixpkgs treat any ShellCheck output as a failing check.
        # Force the check phases to pass and remove any check inputs.
        doCheck = false;
        checkPhase = "true";
        installCheckPhase = "true";
        nativeCheckInputs = [ ];
        checkInputs = [ ];
        doInstallCheck = false;
      });

in
{
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (_final: prev: {
        nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
          _jfinal: _jprev: {
            flashInitrd = ghafFlashInitrd;
            initrdFlashScript = ghafFlashScript;
            flashScript = ghafFlashScript;
          }
        );
      })
    ];
  };
}
