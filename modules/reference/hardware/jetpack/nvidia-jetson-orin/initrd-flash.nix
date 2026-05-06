# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Phase 2 mass-storage handoff for Jetson Orin initrd flash.
#
# Phase 1 (firmware flash, RCM boot, DTS overlay, gadget setup, module list)
# is provided entirely by upstream jetpack-nixos. We only:
#   - extend the device-side initrd via flashScriptOverrides.postFlashInitrdCommands
#     to add a mass_storage LUN backed by /dev/mmcblk0 and signal EMMC_READY
#   - extend the device-side module list with usb_f_mass_storage
#   - wrap upstream's initrdFlashScript on the host side to add the Phase 2
#     loop: detect eMMC-as-USB-mass-storage, sgdisk + dd ESP + dd root,
#     IMAGES_DONE handshake.
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
  inherit (jetpackCfg) flasherPkgs;
  inherit (pkgs.nvidia-jetpack.flashInitrd.passthru) manufacturer product serialnumber;
  serialPortId = "usb-${manufacturer}_${product}_${serialnumber}-if00";

  # Device-side: spliced into upstream jetpack-init after successful firmware
  # flash, before final reboot. PID 1 in the initrd; busybox-only.
  phase2InitrdCommands = lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
    echo "Phase 2: Reconfiguring USB gadget for mass storage..."
    gadget=/sys/kernel/config/usb_gadget/g.1
    UDC_NAME="$(ls /sys/class/udc | head -n 1)"
    if [ -z "$UDC_NAME" ]; then
      echo "ERROR: No UDC enumerated; cannot reconfigure gadget. Aborting Phase 2."
      exit 1
    fi

    # Unbind, add mass_storage function backed by eMMC, rebind composite gadget.
    echo "" >$gadget/UDC
    mkdir $gadget/functions/mass_storage.usb0
    echo /dev/mmcblk0 >$gadget/functions/mass_storage.usb0/lun.0/file
    echo 0 >$gadget/functions/mass_storage.usb0/lun.0/ro
    ln -s $gadget/functions/mass_storage.usb0 $gadget/configs/c.1/
    echo "$UDC_NAME" >$gadget/UDC
    sleep 5
    mdev -s

    ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)
    stty -F $ttyGS 115200 raw -echo -echoe -echok 2>/dev/null || true

    echo "EMMC_READY"
    [ -e "$ttyGS" ] && echo "EMMC_READY" >$ttyGS

    # Wait up to 30 min for host to write images.
    wait_secs=0
    got_done=0
    while [ $wait_secs -lt 1800 ]; do
      if IFS= read -r -t 10 line <"$ttyGS" 2>/dev/null; then
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
      echo "Phase 2 complete."
      # Re-emit upstream's success marker so the host script's final wait succeeds
      # and the operator sees a unified "flash complete" indication.
      [ -e "$ttyGS" ] && echo "Flashing platform firmware successful" >$ttyGS
    fi
  '';

  # Host-side Phase 2 loop. Same semantics as the previous custom version:
  # detect eMMC by VID:PID, partition with sgdisk, dd zstd images,
  # signal IMAGES_DONE on success only.
  phase2HostScript = lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
    phase2_cleanup() {
      echo "ERROR: Host-side failure during Phase 2."
      echo "Device will timeout and reboot in ~30 minutes."
      echo "You can re-run this script after putting the device back in RCM mode."
    }
    trap phase2_cleanup EXIT

    echo "Waiting for device to reconfigure USB (serial + mass storage)..."
    sleep 3
    wait_for_device "$SERIAL_PORT" 60
    configure_serial "$SERIAL_PORT"
    wait_for_message "$SERIAL_PORT" "EMMC_READY" 60

    EMMC_DEV=$(detect_mass_storage 30)
    echo "Found eMMC at: $EMMC_DEV"

    # Unmount any auto-mounted partitions.
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

    echo "IMAGES_DONE" >"$SERIAL_PORT"
    # Best-effort wait for the device's final ack. After IMAGES_DONE is on the
    # wire and sync has succeeded, the flash is complete — the device may reboot
    # before its ack reaches us. Don't let a serial timeout here look like a
    # host-side failure.
    wait_for_message "$SERIAL_PORT" "Flashing platform firmware successful" 30 || true
    echo "Flash complete. Device is rebooting."
    trap - EXIT
  '';

in
{
  config = lib.mkIf cfg.enable {
    # Tell upstream flashInitrd to load the mass-storage gadget module
    # in its initrd module list, and to splice our Phase 2 setup into
    # jetpack-init after the firmware-flash success branch.
    hardware.nvidia-jetpack.flashScriptOverrides = {
      additionalInitrdFlashModules = lib.mkIf (!cfg.flashScriptOverrides.onlyQSPI) [
        "usb_f_mass_storage"
      ];
      postFlashInitrdCommands = phase2InitrdCommands;
    };

    # Replace upstream initrdFlashScript / flashScript with our wrapper.
    # flashInitrd itself is upstream-as-is: we extend it via the hook above,
    # not by overriding the derivation.
    #
    # ghafFlashScript is constructed inside overrideScope so that it can
    # reference _jprev.initrdFlashScript (upstream's pre-override script)
    # for Phase 1. mkRcmBootScript is let-local inside upstream's
    # device-pkgs/default.nix and is NOT exported in the nvidia-jetpack
    # attrset; the only exported entrypoint that performs the correct RCM
    # boot (using flashInitrd + our config's kernel + the DTS overlay set)
    # is initrdFlashScript itself.
    nixpkgs.overlays = [
      (_final: prev: {
        nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
          _jfinal: _jprev:
          let
            # Host-side script: Phase 1 delegates to upstream's initrdFlashScript
            # (which performs the RCM boot using flashInitrd, waits for
            # "Flashing platform firmware successful" via expect, then exits).
            # Phase 2 runs afterwards: detects eMMC-as-USB-mass-storage and writes
            # the Ghaf images. Only built and spliced in when NOT onlyQSPI.
            ghafFlashScript = flasherPkgs.writeShellApplication {
              name = "initrd-flash-${config.networking.hostName}";
              runtimeInputs = with flasherPkgs; [
                gptfdisk
                zstd
                util-linux
                coreutils
              ];
              text = ''
                # --- Phase 1: RCM boot + firmware flash + serial wait ---
                # Upstream's initrdFlashScript (pre-override) performs:
                #   1. RCM boot via mkRcmBootScript (flash.sh --rcm-boot with
                #      flashInitrd + config kernel + DTS overlays)
                #   2. Serial wait (expect) for "Flashing platform firmware successful"
                # It exits 0 on success. Our postFlashInitrdCommands hook has already
                # started running on the device by the time this returns.
                ${lib.getExe _jprev.initrdFlashScript}

                ${
                  if cfg.flashScriptOverrides.onlyQSPI then
                    ''
                      echo "QSPI flash complete. Device is rebooting."
                    ''
                  else
                    ''
                      SERIAL_PORT="/dev/serial/by-id/${serialPortId}"

                      wait_for_device() {
                        local path="$1" timeout="$2" counter=0
                        local max=$((timeout * 2))
                        echo -n "Waiting for $path"
                        while [ ! -e "$path" ] && [ $counter -lt $max ]; do
                          echo -n "."; sleep 0.5; counter=$((counter + 1))
                        done
                        echo
                        [ -e "$path" ] || { echo "ERROR: $path did not appear within ''${timeout}s"; return 1; }
                      }

                      wait_for_message() {
                        local port="$1" msg="$2" timeout="$3"
                        local end=$((SECONDS + timeout))
                        echo "Waiting for message: $msg (timeout: ''${timeout}s)"
                        while [ $SECONDS -lt $end ]; do
                          [ -e "$port" ] || { sleep 1; continue; }
                          if IFS= read -r -t 1 line <"$port" 2>/dev/null; then
                            echo "  [device] $line"
                            case "$line" in
                              *"$msg"*) return 0 ;;
                              *unsuccessful*) echo "ERROR: Device reported failure"; return 1 ;;
                            esac
                          fi
                        done
                        echo "ERROR: Timed out waiting for: $msg"
                        return 1
                      }

                      configure_serial() {
                        local port="$1" retries=10
                        while [ $retries -gt 0 ]; do
                          stty -F "$port" 115200 raw -echo -echoe -echok 2>/dev/null && return 0
                          echo "Waiting for $port to accept tty configuration..."
                          sleep 2; retries=$((retries - 1))
                        done
                        echo "ERROR: $port never became a usable tty" >&2
                        return 1
                      }

                      detect_mass_storage() {
                        local timeout="$1"
                        local end=$((SECONDS + timeout))
                        # Linux Foundation Composite Gadget VID:PID — matches upstream
                        # jetpack-nixos flashInitrd gadget configuration. Update if
                        # upstream changes its identity.
                        local target_vid="1d6b" target_pid="0104"
                        echo "Scanning for USB mass storage device (VID=$target_vid PID=$target_pid)..." >&2
                        while [ $SECONDS -lt $end ]; do
                          for dev in /sys/block/sd*; do
                            [ -e "$dev" ] || continue
                            local devpath
                            devpath=$(readlink -f "$dev/device" 2>/dev/null) || continue
                            echo "$devpath" | grep -q usb || continue
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

                      ${phase2HostScript}
                    ''
                }
              '';
              meta.platforms = [ "x86_64-linux" ];
            };
          in
          {
            initrdFlashScript = ghafFlashScript;
            flashScript = ghafFlashScript;
          }
        );
      })
    ];
  };
}
