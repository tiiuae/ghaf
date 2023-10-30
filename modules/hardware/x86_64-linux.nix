# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.hardware.x86_64.common;
in
  with lib; {
    options.ghaf.hardware.x86_64.common = {
      enable = mkEnableOption "Common x86 configs";
    };

    config = mkIf cfg.enable {
      nixpkgs.hostPlatform.system = "x86_64-linux";

      # Increase the support for different devices by allowing the use
      # of proprietary drivers from the respective vendors
      nixpkgs.config.allowUnfree = true;

      # Add this for x86_64 hosts to be able to more generically support hardware.
      # For example Intel NUC 11's graphics card needs this in order to be able to
      # properly provide acceleration.
      hardware.enableRedistributableFirmware = true;
      hardware.enableAllFirmware = true;

      boot = {
        # Enable normal Linux console on the display
        kernelParams = ["console=tty0"];

        # The initrd has to contain any module that might be necessary for
        # supporting the most important parts of HW like drives.
        initrd.availableKernelModules = [
          # SATA/PATA support.
          "ahci"

          "ata_piix"

          "sata_inic162x"
          "sata_nv"
          "sata_promise"
          "sata_qstor"
          "sata_sil"
          "sata_sil24"
          "sata_sis"
          "sata_svw"
          "sata_sx4"
          "sata_uli"
          "sata_via"
          "sata_vsc"

          "pata_ali"
          "pata_amd"
          "pata_artop"
          "pata_atiixp"
          "pata_efar"
          "pata_hpt366"
          "pata_hpt37x"
          "pata_hpt3x2n"
          "pata_hpt3x3"
          "pata_it8213"
          "pata_it821x"
          "pata_jmicron"
          "pata_marvell"
          "pata_mpiix"
          "pata_netcell"
          "pata_ns87410"
          "pata_oldpiix"
          "pata_pcmcia"
          "pata_pdc2027x"
          "pata_qdi"
          "pata_rz1000"
          "pata_serverworks"
          "pata_sil680"
          "pata_sis"
          "pata_sl82c105"
          "pata_triflex"
          "pata_via"
          "pata_winbond"

          # SCSI support (incomplete).
          "3w-9xxx"
          "3w-xxxx"
          "aic79xx"
          "aic7xxx"
          "arcmsr"
          "hpsa"

          # USB support, especially for booting from USB CD-ROM
          # drives.
          "uas"

          # SD cards.
          "sdhci_pci"

          # NVMe drives
          "nvme"
        ];
        loader = {
          efi.canTouchEfiVariables = true;
          systemd-boot.enable = true;
        };
      };
    };
  }
