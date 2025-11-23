# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Intel Laptop";

  # List of system SKUs covered by this configuration
  skus = [ ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=i915,xe,iwlwifi,snd_hda_intel,snd_sof_pci_intel_tgl,bluetooth,btusb,snd_pcm,mei_me,xesnd_hda_intel,snd_sof_pci_intel_lnl,spi_intel_pci,i801_smbus"
    ];

    # Assign the vfio-pci driver for all device types eligible for passthrough
    # vfio-pci.ids format is vendor:device[:subvendor[:subdevice[:class[:class_mask]]]]
    # 0xffffffff = PCI_ANY_ID
    extraVfioPciIds = [
      "ffffffff:ffffffff:ffffffff:ffffffff:030000:ff0000" # Display Controllers
      "ffffffff:ffffffff:ffffffff:ffffffff:020000:ff0000" # Network Controllers
      "ffffffff:ffffffff:ffffffff:ffffffff:040300:ffff00" # Multimedia Controllers, Audio Devices
    ];
  };

  # Network devices for passthrough to netvm detected dynamically in vhotplug
  # This is left here because google-chromecast service depends on the static network interface name
  # TODO: refactor google-chromecast service to avoid using staticly defined network interface name
  network.pciDevices = [
    {
      name = "wlp0s5f0";
      path = "";
    }
  ];

  # GPU devices generally don't handle hotplugging well
  # However, Intel integrated GPU usually has PCI address 0000:00:02.0, so we can keep it statically defined here
  gpu = {
    pciDevices = [
      {
        path = "0000:00:02.0";
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

  # Audio device for passthrough to audiovm detected dynamically in vhotplug
  audio = {
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
