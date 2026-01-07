# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "System76 darp11-b";

  # List of system SKUs covered by this configuration
  skus = [
    "Not Specified Darter Pro"
  ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "module_blacklist=e1000e,i2c_i801,i915,iwlwifi,snd_hda_intel,snd_sof_pci_intel_mtl,spi_intel_pci,bluetooth,btusb,xe"
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        # "AT Translated Set 2 keyboard" "Power Button" "HDA Intel PCH Headphone" "HDA Intel PCH HDMI/DP,pcm=3" "HDA Intel PCH HDMI/DP,pcm=7" "HDA Intel PCH HDMI/DP,pcm=8" "HDA Intel PCH HDMI/DP,pcm=9" "Sleep Button" "Lid Switch" "System76 ACPI Hotkeys" "Video Bus"
        "Intel HID events"
      ];
      evdev = [
        # /dev/input/by-path/platform-i8042-serio-0-event-kbd
        "/dev/input/by-path/platform-INT33D5:00-event"
      ];
    };
  };

  # Network devices for passthrough to netvm
  network = {
    pciDevices = [
      {
        # Network controller: Intel Corporation Wi-Fi 7(802.11be) AX1775*/AX1790*/BE20*/BE401/BE1750* 2x2 (rev 1a)
        name = "wlp0s5f0";
        path = ""; # PCI ID will be retrieved dynamically see https://github.com/tiiuae/ghaf/pull/1220/files
        vendorId = "8086";
        productId = "272b";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
      {
        # Ethernet controller: Intel Corporation Device 550a
        # NOTE: This device is in the same IOMMU group as audio devices (0000:00:1f.x).
        # PCI ACS override is enabled in the laptop configuration to split this group.
        name = "eth0";
        path = "0000:00:1f.6";
        vendorId = "8086";
        productId = "550a";
        # Detected kernel driver: e1000e
        # Detected kernel modules: e1000e
      }
    ];
    kernelConfig = {
      stage2.kernelModules = [
        "e1000e"
      ];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: Intel Corporation Arrow Lake-P [Intel Graphics] (rev 03)
        name = "gpu0";
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "7d51";
        # Detected kernel driver: i915
        # Detected kernel modules: i915,xe
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [
        "i915"
      ];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    acpiPath = null;

    pciDevices = [
      {
        # ISA bridge: Intel Corporation Device 7702
        name = "snd0-0";
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "7702";
        # Detected kernel driver:
        # Detected kernel modules:
      }
      {
        # Serial bus controller: Intel Corporation Device 7723
        name = "snd0-1";
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "7723";
        # Detected kernel driver:
        # Detected kernel modules:
      }
      {
        # Audio device: Intel Corporation Device 7728
        name = "snd0-2";
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "7728";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel,snd_sof_pci_intel_mtl
      }
      {
        # SMBus: Intel Corporation Device 7722
        name = "snd0-3";
        path = "0000:00:1f.4";
        vendorId = "8086";
        productId = "7722";
        # Detected kernel driver: i801_smbus
        # Detected kernel modules: i2c_i801
      }
    ];
    kernelConfig = {
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_mtl"
        "spi_intel_pci"
      ];
    };
  };

  # USB devices for passthrough
  usb.devices = [
    # Integrated camera
    {
      name = "cam0";
      hostbus = "3";
      hostport = "7";
    }
    # Bluetooth controller
    {
      name = "bt0";
      hostbus = "3";
      hostport = "10";
    }
  ];
}
