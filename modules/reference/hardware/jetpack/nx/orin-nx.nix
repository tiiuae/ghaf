# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{
  pkgs,
  ...
}:
{
  _file = ./orin-nx.nix;

  imports = [ ../../../../common/services/hwinfo ];

  ghaf = {
    # Enable hardware info generation on host
    services.hwinfo = {
      enable = true;
      outputDir = "/var/lib/ghaf-hwinfo";
    };

    hardware = {
      nvidia.orin = {
        enable = true;
        kernelVersion = "upstream-6-6";
        somType = "nx";
        nx.enableNetvmEthernetPCIPassthrough = true;
        carrierBoard = "xavierNxDevkit";
        # Orin NX p3768 devkit boots rootfs from NVMe (no eMMC on this SoM);
        # configFileName below wires up the matching .conf + flash XML.
        flashScriptOverrides.rootfsDevice = "nvme0n1p1";
      };

      # Net VM hardware-specific modules - use hardware.definition for composition model
      definition.netvm.extraModules = [
        {
          # The Nvidia Orin hardware dependent configuration is in
          # modules/reference/hardware/jetpack Please refer to that
          # section for hardware dependent netvm configuration.

          # Wireless Configuration. Orin AGX has WiFi enabled where Orin NX does
          # not.

        }
        # Hardware info guest support
        {
          imports = [ ../../../../common/services/hwinfo ];
          ghaf.services.hwinfo-guest.enable = true;
        }
        # Ensure hardware info is generated before net-vm starts
        {
          systemd.services."microvm@net-vm" = {
            wants = [ "ghaf-hwinfo-generate.service" ];
            after = [ "ghaf-hwinfo-generate.service" ];
          };
        }
        # QEMU arguments to pass hardware info via fw_cfg
        {
          microvm.qemu.extraArgs = [
            "-fw_cfg"
            "name=opt/com.ghaf.hwinfo,file=/var/lib/ghaf-hwinfo/hwinfo.json"
          ];
        }
        ../../../personalize
        { ghaf.reference.personalize.keys.enable = true; }
      ];
    };
  };

  hardware = {
    # Sake of clarity: Jetson 35.4 and IO BASE B carrier board
    # uses "tegra234-p3767-0000-p3509-a02.dtb"-device tree.
    # p3509-a02 == IO BASE B carrier board
    # p3767-0000 == Orin NX SOM
    # p3768-0000 == Official NVIDIA's carrier board
    # Upstream kernel has only official carrier board device tree,
    # but it works with IO BASE B carrier board with minor
    # modifications.
    deviceTree.name = "tegra234-p3768-0000+p3767-0000-nv.dtb";
    nvidia-jetpack = {
      enable = true;
      som = "orin-nx";
      # p3768 official devkit, matching the p3768 deviceTree above.
      # "xavierNxDevkit" maps to p3509-a02 + eMMC, which the Orin NX SOM
      # does not have.
      carrierBoard = "devkit";
      # carrierBoard "devkit" defaults configFileName to
      # "jetson-orin-nano-devkit", whose .conf flashes a QSPI+SD/eMMC layout.
      # The p3768 NX board has no eMMC, so MB2 fails to init SDMMC instance 3
      # ("Secondary storage init failed" on UART) and hangs in Busy Spin.
      # The "-nvme" config sources p3768-0000-p3767-0000-a0.conf and uses
      # flash_t234_qspi_nvme.xml, which probes NVMe instead.
      flashScriptOverrides.configFileName = "jetson-orin-nano-devkit-nvme";
      # The trailing rootfs device passed to flash.sh is now driven by
      # ghaf.hardware.nvidia.orin.flashScriptOverrides.rootfsDevice (set
      # to "nvme0n1p1" above); jetson-orin.nix applies that to flashArgs.
      modesetting.enable = true;
      firmware.uefi = {
        logo = "${pkgs.ghaf-artwork}/1600px-Ghaf_logo.svg";
        edk2NvidiaPatches = [
          # This effectively disables EFI FB Simple Framebuffer, which does
          # not work properly but causes kernel panic during the boot if the
          # HDMI cable is connected during boot time.
          #
          # The patch reverts back to old behavior, which is to always reset
          # the display when exiting UEFI, instead of doing handoff, when
          # means not to reset anything.
          # ./edk2-nvidia-always-reset-display.patch
        ];
      };
    };
  };
}
