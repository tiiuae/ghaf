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
  serialPortId = "usb-${manufacturer}_${product}_${serialnumber}-if00";

  ghafFlashInit = pkgs.writeScript "init" ''
    #!${pkgs.pkgsStatic.busybox}/bin/sh
    export PATH=${pkgs.pkgsStatic.busybox}/bin
    mkdir -p /proc /dev /sys
    mount -t proc proc -o nosuid,nodev,noexec /proc
    mount -t devtmpfs none -o nosuid /dev
    mount -t sysfs sysfs -o nosuid,nodev,noexec /sys
    ln -s /proc/self/fd /dev/

    for mod in ${toString modules}; do
      modprobe -v $mod
    done

    mount -t configfs none /sys/kernel/config
    if [ -e /sys/kernel/config/usb_gadget ] ; then
      gadget=/sys/kernel/config/usb_gadget/g.1
      mkdir $gadget

      echo 0x1d6b >$gadget/idVendor
      echo 0x104 >$gadget/idProduct

      mkdir $gadget/strings/0x409
      echo ${manufacturer} >$gadget/strings/0x409/manufacturer
      echo ${product} >$gadget/strings/0x409/product
      echo ${serialnumber} >$gadget/strings/0x409/serialnumber

      mkdir $gadget/configs/c.1
      mkdir $gadget/functions/acm.usb0

      ln -s $gadget/functions/acm.usb0 $gadget/configs/c.1/

      if [ -w /sys/bus/usb/devices/usb2/power/control ] ; then
        echo on >/sys/bus/usb/devices/usb2/power/control
      fi

      while [ -z "$(ls /sys/class/udc | head -n 1)" ] ; do
        echo "Waiting for /sys/class/udc/*"
        sleep 1
      done

      UDC_NAME="$(ls /sys/class/udc | head -n 1)"
      echo "$UDC_NAME" >$gadget/UDC

      if [ -w /sys/class/usb_role/usb2-0-role-switch/role ] ; then
        echo device > /sys/class/usb_role/usb2-0-role-switch/role
      fi

      sleep 5
      mdev -s

      ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)
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
      [ -e "$ttyGS" ] && echo "Flashing platform firmware unsuccessful." > $ttyGS
      ${lib.optionalString (jetpackCfg.firmware.secureBoot.pkcFile == null) ''
        echo "Entering console"
        exec ${pkgs.pkgsStatic.busybox}/bin/sh
      ''}
      sleep 30
      reboot -f
    fi
    echo "FIRMWARE_DONE"
    [ -e "$ttyGS" ] && echo "FIRMWARE_DONE" > $ttyGS

    ${
      if cfg.flashScriptOverrides.onlyQSPI then
        ''
          echo "============================================================"
          echo "Flashing platform firmware successful"
          echo "============================================================"
          [ -e "$ttyGS" ] && echo "Flashing platform firmware successful" > $ttyGS
          sync
          reboot -f
        ''
      else
        ''
          # Phase 2: Expose eMMC as USB mass storage
          echo "Phase 2: Reconfiguring USB gadget for mass storage..."

          # Unbind gadget from UDC
          echo "" >$gadget/UDC

          # Create mass storage function
          mkdir $gadget/functions/mass_storage.usb0
          echo /dev/mmcblk0 >$gadget/functions/mass_storage.usb0/lun.0/file
          echo 0 >$gadget/functions/mass_storage.usb0/lun.0/ro

          # Add mass storage to configuration
          ln -s $gadget/functions/mass_storage.usb0 $gadget/configs/c.1/

          # Rebind composite gadget (ACM serial + mass storage)
          echo "$UDC_NAME" >$gadget/UDC

          sleep 5
          mdev -s

          # Re-read serial device path after gadget reconnect
          ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)

          echo "EMMC_READY"
          [ -e "$ttyGS" ] && echo "EMMC_READY" > $ttyGS

          # Wait for host to finish writing images (timeout: 30 min)
          echo "Waiting for host to write OS images..."
          wait_secs=0
          got_done=0
          while [ $wait_secs -lt 1800 ]; do
            if IFS= read -r -t 10 line < $ttyGS 2>/dev/null; then
              echo "  [host] $line"
              case "$line" in
                IMAGES_DONE*) got_done=1; break ;;
              esac
            fi
            wait_secs=$((wait_secs + 10))
          done

          if [ $got_done -eq 0 ]; then
            echo "ERROR: Timed out waiting for host (30 min). Rebooting."
          else
            echo "============================================================"
            echo "Flashing platform firmware successful"
            echo "============================================================"
            [ -e "$ttyGS" ] && echo "Flashing platform firmware successful" > $ttyGS
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

  ghafFlashScript = flasherPkgs.writeShellApplication {
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

      SERIAL_PORT="/dev/serial/by-id/${serialPortId}"

      wait_for_device() {
        local path="$1"
        local timeout="$2"
        local counter=0
        local max=$((timeout * 2))
        echo -n "Waiting for $path"
        while [ ! -e "$path" ] && [ $counter -lt $max ]; do
          echo -n "."
          sleep 0.5
          counter=$((counter + 1))
        done
        echo
        if [ ! -e "$path" ]; then
          echo "ERROR: $path did not appear within ''${timeout}s"
          return 1
        fi
      }

      wait_for_message() {
        local port="$1"
        local msg="$2"
        local timeout="$3"
        local end=$((SECONDS + timeout))
        echo "Waiting for message: $msg (timeout: ''${timeout}s)"
        while [ $SECONDS -lt $end ]; do
          if [ ! -e "$port" ]; then
            sleep 1
            continue
          fi
          if IFS= read -r -t 1 line < "$port" 2>/dev/null; then
            echo "  [device] $line"
            case "$line" in
              *"$msg"*) return 0 ;;
              *"unsuccessful"*)
                echo "ERROR: Device reported failure"
                return 1
                ;;
            esac
          fi
        done
        echo "ERROR: Timed out waiting for: $msg"
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

      # Wait for device serial port to appear
      wait_for_device "$SERIAL_PORT" 240

      # Configure serial port for raw I/O
      stty -F "$SERIAL_PORT" 115200 raw -echo -echoe -echok

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
            trap phase2_cleanup EXIT

            # Serial will disconnect briefly during gadget reconfiguration
            echo "Waiting for device to reconfigure USB (serial + mass storage)..."
            sleep 3
            wait_for_device "$SERIAL_PORT" 60

            # Reconfigure serial after reconnect
            stty -F "$SERIAL_PORT" 115200 raw -echo -echoe -echok

            wait_for_message "$SERIAL_PORT" "EMMC_READY" 60

            # Detect eMMC mass storage device
            EMMC_DEV=$(detect_mass_storage 30)
            echo "Found eMMC at: $EMMC_DEV"

            # Unmount any auto-mounted partitions (desktop environments may auto-mount)
            for part in "''${EMMC_DEV}"*; do
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
            blockdev --rereadpt "$EMMC_DEV"
            sleep 2

            FLASH_IMAGES="${ghafFlashImages}"
            echo "Writing ESP image to ''${EMMC_DEV}1..."
            zstd -d "$FLASH_IMAGES/esp.img.zst" --stdout | dd of="''${EMMC_DEV}1" bs=4M status=progress
            echo "Writing root image to ''${EMMC_DEV}2..."
            zstd -d "$FLASH_IMAGES/root.img.zst" --stdout | dd of="''${EMMC_DEV}2" bs=4M status=progress
            sync

            # Signal completion to device
            trap - EXIT
            echo "IMAGES_DONE" > "$SERIAL_PORT"

            # Wait for device to confirm and reboot
            wait_for_message "$SERIAL_PORT" "Flashing platform firmware successful" 30

            echo "Flash complete. Device is rebooting."
          ''
      }
    '';
    meta.platforms = [ "x86_64-linux" ];
  };
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
