# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.thor;

  nvmeGadgetScript = ''
    echo "Thor NVMe Flash via USB Mass Storage"
    echo ""

    echo "Loading PCIe, NVMe and USB modules..."
    modprobe phy_tegra194_p2u || echo "WARN: phy_tegra194_p2u module load failed"
    modprobe pcie-tegra264 || echo "WARN: pcie-tegra264 module load failed"

    sleep 2

    modprobe nvme_core || echo "WARN: nvme_core module load failed"
    modprobe nvme || echo "WARN: nvme module load failed"
    modprobe usb_f_mass_storage || echo "WARN: usb_f_mass_storage module load failed"
    modprobe vfat || echo "WARN: vfat module load failed"

    echo "Loaded modules:"
    lsmod | grep -E "pcie|tegra|nvme|usb_f|vfat" || echo "  (none matching)"

    echo "Block devices:"
    ls -la /dev/nvme* /dev/sd* /dev/mmcblk* 2>/dev/null || echo "  (no block devices found)"

    # Wait for Thor's NVMe device
    SECONDS=0
    TIMEOUT=30
    echo "Waiting for NVMe device (timeout: $TIMEOUT seconds)..."
    while [ ! -b /dev/nvme0n1 ] && [ $SECONDS -lt $TIMEOUT ]; do
      sleep 1
      [ $((SECONDS % 10)) -eq 0 ] && echo "  ...''${SECONDS}s"
    done

    if [ ! -b /dev/nvme0n1 ]; then
      echo "ERROR: NVMe device /dev/nvme0n1 not found after ''${SECONDS}s"
      echo "Final block devices:"
      ls -la /dev/nvme* /dev/sd* /dev/mmcblk* 2>/dev/null || echo "  (none)"
      exit 1
    fi

    nvme_size=$(( $(cat /sys/block/nvme0n1/size) * 512 ))
    echo "NVMe device found: /dev/nvme0n1 ($nvme_size bytes)"

    # Configuring USB gadget
    gadget=/sys/kernel/config/usb_gadget/g.1
    if [ ! -d "$gadget" ]; then
      echo "ERROR: USB gadget not configured"
      exit 1
    fi

    echo "Exposing NVMe as USB mass storage..."
    udc=$(cat "$gadget/UDC" 2>/dev/null || true)
    [ -n "$udc" ] && echo "" > "$gadget/UDC"

    # Set identifiable gadget strings for auto-detection
    echo "GHAF-THOR-NVME" > "$gadget/strings/0x409/serialnumber"

    mkdir -p "$gadget/functions/mass_storage.0"
    echo 0 > "$gadget/functions/mass_storage.0/lun.0/ro"
    echo "/dev/nvme0n1" > "$gadget/functions/mass_storage.0/lun.0/file"
    ln -sf "$gadget/functions/mass_storage.0" "$gadget/configs/c.1/"
    echo "$(ls /sys/class/udc | head -n 1)" > "$gadget/UDC"

    sleep 2

    echo ""
    echo "NVMe exposed. Waiting for host to write images..."
    echo ""

    # Wait for completion marker on ESP
    SECONDS=0
    TIMEOUT=600
    echo "Waiting for host to complete flash (timeout: $TIMEOUT seconds)..."
    while [ $SECONDS -lt $TIMEOUT ]; do
      sleep 5

      if [ -b /dev/nvme0n1p1 ]; then
        mkdir -p /mnt/esp
        if mount -t vfat /dev/nvme0n1p1 /mnt/esp 2>/dev/null; then
          while [ $SECONDS -lt $TIMEOUT ]; do
            if [ -f /mnt/esp/.flash_complete ]; then
              echo "Host completed NVMe flash!"
              rm -f /mnt/esp/.flash_complete
              umount /mnt/esp
              break 2
            fi
            sleep 5
          done
          umount /mnt/esp
        fi
      else
        printf "."
      fi
    done
  '';
in
{
  config = lib.mkIf cfg.enable {

    hardware.nvidia-jetpack.flashScriptOverrides.additionalInitrdFlashModules = [
      "pcie-tegra264"
      "phy_tegra194_p2u"
      "nvme_core"
      "nvme"
      "usb_f_mass_storage"
      "vfat"
    ];

    hardware.nvidia-jetpack.flashScriptOverrides.postFlashDeviceCommands = nvmeGadgetScript;
  };
}
