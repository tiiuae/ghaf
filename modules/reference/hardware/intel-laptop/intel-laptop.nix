# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Intel Laptop";

  # List of system SKUs covered by this configuration
  skus = [ ];

  # Host configuration
  host = {
    kernelConfig = {
      kernelParams = [
        "intel_iommu=on,sm_on"
        "iommu=pt"
        "acpi_backlight=vendor"
        "acpi_osi=linux"
        # `xe,` had lost its comma and read `xesnd_hda_intel`, which is not a
        # module -- so the i915 rival driver was never blacklisted on the host
        "module_blacklist=iwlwifi,snd_hda_intel,snd_sof_pci_intel_tgl,bluetooth,btusb,snd_pcm,mei_me,xe,snd_sof_pci_intel_lnl,spi_intel_pci,i801_smbus,nouveau,nvidia,nvidiafb,i2c_nvidia_gpu"
      ];
      stage1.kernelModules = [
        # Load i915 in the host initrd as a hardware workaround: some laptop models
        # need the host to initialize the display pipeline early, otherwise the GUI VM
        # may boot with a broken or non-functional screen.
        "i915"
      ];
    };

    # Assign the vfio-pci driver for all device types eligible for passthrough
    # vfio-pci.ids format is vendor:device[:subvendor[:subdevice[:class[:class_mask]]]]
    # 0xffffffff = PCI_ANY_ID
    extraVfioPciIds = [
      "ffffffff:ffffffff:ffffffff:ffffffff:030000:ff0000" # Display Controllers
      "ffffffff:ffffffff:ffffffff:ffffffff:020000:ff0000" # Network Controllers
      "ffffffff:ffffffff:ffffffff:ffffffff:040300:ffff00" # Multimedia Controllers, Audio Devices
    ];
  };

  # Network devices for passthrough to netvm are detected dynamically in vhotplug.
  #
  # This entry is NOT a passthrough declaration -- it has no PCI path, so it is
  # skipped for passthrough (devices.nix filters on path/vendor+product). What it
  # does is generate a systemd.link rule matching Type=wlan, giving whichever
  # wireless device shows up the stable name below. That is still worth having.
  #
  # It used to exist for a second reason: chromecast and friends took
  # `(lib.head network.pciDevices).name` as "the external NIC". That was wrong on
  # any wired device -- ethernet arrives as a dock or dongle via vhotplug and is
  # not in this list at all -- and is now resolved at runtime by
  # ghaf-uplink-resolver instead. Nothing derives the uplink from here any more.
  network = {
    pciDevices = [
      {
        name = "wlp0s5f0";
        path = "";
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "iwlwifi"
        "e1000e"
      ];
      kernelParams = [ ];
    };
  };

  # GPU devices for passthrough to guivm detected dynamically in vhotplug
  gpu = {
    kernelConfig = {
      stage1.kernelModules = [
        "i915"
      ];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # Audio device for passthrough to audiovm detected dynamically in vhotplug
  audio = {
    # This is used to pass the NHLT ACPI table from the host to audio-vm (/sys/firmware/acpi/tables/NHLT)
    # It is required to enable the Lenovo X1 microphone array profile
    # The NHLT table may not exist on other systems so it is disabled here and managed dynamically by vhotplug
    acpiPath = null;

    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_tgl"
        "spi_intel_pci"
        "snd_soc_avs"
      ];
      kernelParams = [ ];
    };
  };
}
