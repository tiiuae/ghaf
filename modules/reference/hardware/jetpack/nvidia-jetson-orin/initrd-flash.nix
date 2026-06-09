# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Phase 2 mass-storage handoff for Jetson Orin initrd flash.
#
# Phase 1 (firmware flash, RCM boot, DTS overlay, gadget setup, module list)
# is provided entirely by upstream jetpack-nixos. We only:
#   - extend the device-side initrd via flashScriptOverrides.postFlashInitrdCommands
#     to negotiate a target rootfs drive with the host, add a mass_storage
#     LUN backed by that drive, and signal STORAGE_READY
#   - extend the device-side module list with usb_f_mass_storage + the
#     drivers needed to access NVMe / USB-storage candidate targets
#   - wrap upstream's initrdFlashScript on the host side to:
#       - accept a `--target=emmc|nvme|usb` CLI flag (default emmc)
#       - drive Phase 2: validate target against device-advertised set,
#         detect drive-as-USB-mass-storage, sgdisk + dd ESP + dd root,
#         IMAGES_DONE handshake.
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
  #
  # Protocol (over the existing ACM gadget serial):
  #   1. Device probes candidate drives (emmc, nvme, usb), advertises the
  #      ones present as "AVAILABLE_TARGETS=<comma-list>".
  #   2. Host responds with "SELECT_TARGET=<name>" (validated against list).
  #   3. Device unbinds the gadget, adds a mass_storage LUN backed by the
  #      chosen drive, re-binds, then announces "STORAGE_READY".
  #   4. Host partitions + dd's, sends "IMAGES_DONE".
  #   5. Device re-emits upstream's success marker so the host's expect
  #      watcher can finish cleanly.
  phase2InitrdCommands = lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
    echo "Phase 2: Target selection..."
    gadget=/sys/kernel/config/usb_gadget/g.1
    UDC_NAME="$(ls /sys/class/udc | head -n 1)"
    if [ -z "$UDC_NAME" ]; then
      echo "ERROR: No UDC enumerated; cannot reconfigure gadget. Aborting Phase 2."
      exit 1
    fi

    ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)
    stty -F $ttyGS 115200 raw -echo -echoe -echok 2>/dev/null || true

    # Probe candidate drives. NVMe/USB-storage may enumerate slower than eMMC,
    # so give each up to 10s after upstream init has handed off.
    AVAIL=""
    for entry in "mmcblk0:emmc" "nvme0n1:nvme" "sda:usb"; do
      dev=''${entry%:*}
      tag=''${entry##*:}
      waited=0
      while [ $waited -lt 10 ] && [ ! -b /dev/$dev ]; do sleep 1; waited=$((waited+1)); done
      if [ -b /dev/$dev ]; then
        AVAIL="''${AVAIL:+$AVAIL,}$tag"
      fi
    done
    if [ -z "$AVAIL" ]; then
      echo "ERROR: no candidate rootfs drive present (mmcblk0/nvme0n1/sda). Aborting Phase 2."
      exit 1
    fi
    echo "AVAILABLE_TARGETS=$AVAIL"
    [ -e "$ttyGS" ] && echo "AVAILABLE_TARGETS=$AVAIL" >$ttyGS

    # Wait up to 60s for host to choose.
    SELECTED=""
    waited=0
    while [ $waited -lt 60 ]; do
      if IFS= read -r -t 5 line <"$ttyGS" 2>/dev/null; then
        case "$line" in
          SELECT_TARGET=*) SELECTED="''${line#SELECT_TARGET=}"; break ;;
        esac
      fi
      waited=$((waited+5))
    done
    case "$SELECTED" in
      emmc) LUN_BACKING=/dev/mmcblk0 ;;
      nvme) LUN_BACKING=/dev/nvme0n1 ;;
      usb)  LUN_BACKING=/dev/sda ;;
      *)    echo "ERROR: invalid or missing target selection ('$SELECTED'). Aborting."; exit 1 ;;
    esac
    if [ ! -b "$LUN_BACKING" ]; then
      echo "ERROR: chosen target '$SELECTED' ($LUN_BACKING) disappeared before LUN setup."
      exit 1
    fi

    echo "Reconfiguring USB gadget for mass storage backed by $LUN_BACKING..."
    echo "" >$gadget/UDC
    mkdir $gadget/functions/mass_storage.usb0
    echo $LUN_BACKING >$gadget/functions/mass_storage.usb0/lun.0/file
    echo 0 >$gadget/functions/mass_storage.usb0/lun.0/ro
    ln -s $gadget/functions/mass_storage.usb0 $gadget/configs/c.1/
    echo "$UDC_NAME" >$gadget/UDC
    sleep 5
    mdev -s

    # Gadget bounced: ttyGS may have moved. Re-resolve and reconfigure.
    ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)
    stty -F $ttyGS 115200 raw -echo -echoe -echok 2>/dev/null || true

    echo "STORAGE_READY: target=$SELECTED dev=$LUN_BACKING"
    [ -e "$ttyGS" ] && echo "STORAGE_READY" >$ttyGS

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

  # Host-side Phase 2 loop. Mirrors the device-side protocol: read
  # AVAILABLE_TARGETS, validate the --target flag against it, send
  # SELECT_TARGET, wait for STORAGE_READY, partition + dd, signal
  # IMAGES_DONE on success only.
  phase2HostScript = lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
    phase2_cleanup() {
      echo "ERROR: Host-side failure during Phase 2."
      echo "Device will timeout and reboot in ~30 minutes."
      echo "You can re-run this script after putting the device back in RCM mode."
    }
    trap phase2_cleanup EXIT

    echo "Waiting for device serial (post-firmware)..."
    sleep 3
    wait_for_device "$SERIAL_PORT" 60
    configure_serial "$SERIAL_PORT"

    AVAIL=$(read_message_value "$SERIAL_PORT" "AVAILABLE_TARGETS" 60)
    if [ -z "$AVAIL" ]; then
      echo "ERROR: device did not advertise AVAILABLE_TARGETS within 60s."
      exit 1
    fi
    echo "Device offers targets: $AVAIL"
    case ",$AVAIL," in
      *,"$FLASH_TARGET",*) echo "Selecting target: $FLASH_TARGET" ;;
      *) echo "ERROR: requested --target=$FLASH_TARGET but device only has: $AVAIL"; exit 1 ;;
    esac
    echo "SELECT_TARGET=$FLASH_TARGET" >"$SERIAL_PORT"

    # Device unbinds + rebinds gadget. Serial port disappears briefly.
    wait_for_message "$SERIAL_PORT" "STORAGE_READY" 90

    STORAGE_DEV=$(detect_mass_storage 30)
    echo "Found mass-storage device at: $STORAGE_DEV (target=$FLASH_TARGET)"

    # Unmount any auto-mounted partitions.
    for part in "''${STORAGE_DEV}"*; do
      if mountpoint -q "$(findmnt -n -o TARGET "$part" 2>/dev/null)" 2>/dev/null; then
        echo "Unmounting auto-mounted $part..."
        umount "$part" 2>/dev/null || umount -l "$part" 2>/dev/null || true
      fi
    done

    echo "Creating GPT partition table on $STORAGE_DEV..."
    sgdisk --zap-all "$STORAGE_DEV"
    sgdisk --new=1:0:+256M --typecode=1:EF00 --change-name=1:FIRMWARE "$STORAGE_DEV"
    sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:NIXOS_ROOT "$STORAGE_DEV"
    sgdisk --print "$STORAGE_DEV"
    blockdev --rereadpt "$STORAGE_DEV"
    sleep 2

    # NVMe partition device nodes use a 'p' suffix (e.g. nvme0n1p1) while
    # mmc / sd use a bare index. detect_mass_storage returns the parent
    # device node as it appears on the host (typically /dev/sdX), so the
    # bare index works on the host side regardless of how the chosen drive
    # is named on the device. $FLASH_IMAGES comes from CLI / default
    # (see arg parsing above).
    echo "Writing ESP image to ''${STORAGE_DEV}1..."
    zstd -d "$FLASH_IMAGES/esp.img.zst" --stdout | dd of="''${STORAGE_DEV}1" bs=4M status=progress
    echo "Writing root image to ''${STORAGE_DEV}2..."
    zstd -d "$FLASH_IMAGES/root.img.zst" --stdout | dd of="''${STORAGE_DEV}2" bs=4M status=progress
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
        # USB Mass Storage gadget function.
        "usb_f_mass_storage"
        # NVMe stack (target=nvme).
        "nvme"
        "nvme_core"
        # USB Mass Storage host-side stack (target=usb).
        "usb_storage"
        "uas"
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
                jq
              ];
              text = ''
                # --- CLI argument parsing ---
                FLASH_TARGET=emmc
                # Default flash-images dir is the one this derivation was built with
                # (closure-bundled). Override via --flash-images=DIR to use an
                # artifact set produced elsewhere (e.g. Jenkins-built, copied to
                # the test agent's filesystem).
                FLASH_IMAGES="${ghafFlashImages}"
                EXPECTED_HOST_NAME="${config.networking.hostName}"
                EXPECTED_SCHEMA_VERSION=1
                while [ $# -gt 0 ]; do
                  case "$1" in
                    --target=*)        FLASH_TARGET=''${1#*=} ;;
                    --target)          shift; FLASH_TARGET=''${1:-} ;;
                    --flash-images=*)  FLASH_IMAGES=''${1#*=} ;;
                    --flash-images)    shift; FLASH_IMAGES=''${1:-} ;;
                    -h|--help)
                      cat <<USAGE
                Usage: $(basename "$0") [--target=emmc|nvme|usb] [--flash-images=DIR]

                  --target         Destination drive for the NixOS rootfs (default: emmc).
                                   'emmc' targets /dev/mmcblk0 on the device.
                                   'nvme' targets /dev/nvme0n1 (requires an M.2 NVMe present).
                                   'usb'  targets /dev/sda    (requires a USB drive attached
                                                                to a host-mode USB port).
                                   The chosen target must be detected on the device; otherwise
                                   the script aborts before any partition is touched.

                  --flash-images   Directory containing esp.img.zst + root.img.zst +
                                   flash-manifest.json (the output of the
                                   <target>-flash-images flake package). Default is the
                                   path baked into this script at build time; override to
                                   use artifacts copied from a build host.
                USAGE
                                      exit 0 ;;
                                    *) echo "ERROR: unknown argument '$1'. Use --help." >&2; exit 1 ;;
                                  esac
                                  shift
                                done
                                case "$FLASH_TARGET" in
                                  emmc|nvme|usb) ;;
                                  *) echo "ERROR: --target must be one of emmc, nvme, usb (got '$FLASH_TARGET')." >&2; exit 1 ;;
                                esac

                                # --- Validate --flash-images directory + manifest ---
                                if [ ! -d "$FLASH_IMAGES" ]; then
                                  echo "ERROR: --flash-images: '$FLASH_IMAGES' is not a directory." >&2
                                  exit 1
                                fi
                                if [ ! -f "$FLASH_IMAGES/flash-manifest.json" ]; then
                                  echo "ERROR: --flash-images: '$FLASH_IMAGES/flash-manifest.json' missing. The directory must be a <target>-flash-images package output." >&2
                                  exit 1
                                fi
                                MANIFEST_SCHEMA=$(jq -r '.schema_version' "$FLASH_IMAGES/flash-manifest.json")
                                MANIFEST_HOST=$(jq -r '.host_name' "$FLASH_IMAGES/flash-manifest.json")
                                MANIFEST_TRANSPORT=$(jq -r '.transport' "$FLASH_IMAGES/flash-manifest.json")
                                if [ "$MANIFEST_SCHEMA" != "$EXPECTED_SCHEMA_VERSION" ]; then
                                  echo "ERROR: manifest schema_version=$MANIFEST_SCHEMA, this flasher expects $EXPECTED_SCHEMA_VERSION." >&2
                                  exit 1
                                fi
                                if [ "$MANIFEST_HOST" != "$EXPECTED_HOST_NAME" ]; then
                                  echo "ERROR: manifest host_name=$MANIFEST_HOST, this flasher was built for $EXPECTED_HOST_NAME. Refusing to flash mismatched images." >&2
                                  exit 1
                                fi
                                ${
                                  if cfg.flashScriptOverrides.onlyQSPI then
                                    ''
                                      if [ "$MANIFEST_TRANSPORT" != "qspi-only" ]; then
                                        echo "ERROR: manifest transport=$MANIFEST_TRANSPORT, this flasher is qspi-only." >&2
                                        exit 1
                                      fi
                                      if [ "$FLASH_TARGET" != emmc ]; then
                                        echo "WARNING: --target=$FLASH_TARGET is ignored by the QSPI-only flasher (no rootfs is written)." >&2
                                      fi
                                    ''
                                  else
                                    ''
                                      if [ "$MANIFEST_TRANSPORT" != "initrd-mass-storage" ]; then
                                        echo "ERROR: manifest transport=$MANIFEST_TRANSPORT, this flasher expects initrd-mass-storage." >&2
                                        exit 1
                                      fi
                                      for f in esp.img.zst root.img.zst; do
                                        if [ ! -f "$FLASH_IMAGES/$f" ]; then
                                          echo "ERROR: required artifact '$f' missing from $FLASH_IMAGES." >&2
                                          exit 1
                                        fi
                                      done
                                      echo "Flash target drive: $FLASH_TARGET"
                                      echo "Flash images:       $FLASH_IMAGES"
                                    ''
                                }

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
                                        echo "Waiting for message: $msg (timeout: ''${timeout}s)" >&2
                                        while [ $SECONDS -lt $end ]; do
                                          [ -e "$port" ] || { sleep 1; continue; }
                                          if IFS= read -r -t 1 line <"$port" 2>/dev/null; then
                                            echo "  [device] $line" >&2
                                            case "$line" in
                                              *"$msg"*) return 0 ;;
                                              *unsuccessful*) echo "ERROR: Device reported failure" >&2; return 1 ;;
                                            esac
                                          fi
                                        done
                                        echo "ERROR: Timed out waiting for: $msg" >&2
                                        return 1
                                      }

                                      # Read a "KEY=value" line from the device serial and print
                                      # the value (without the trailing newline) on stdout.
                                      read_message_value() {
                                        local port="$1" key="$2" timeout="$3"
                                        local end=$((SECONDS + timeout))
                                        echo "Waiting for $key=... (timeout: ''${timeout}s)" >&2
                                        while [ $SECONDS -lt $end ]; do
                                          [ -e "$port" ] || { sleep 1; continue; }
                                          if IFS= read -r -t 1 line <"$port" 2>/dev/null; then
                                            echo "  [device] $line" >&2
                                            case "$line" in
                                              "$key="*) printf '%s' "''${line#"$key="}"; return 0 ;;
                                              *unsuccessful*) echo "ERROR: Device reported failure" >&2; return 1 ;;
                                            esac
                                          fi
                                        done
                                        echo "ERROR: Timed out waiting for $key=..." >&2
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
