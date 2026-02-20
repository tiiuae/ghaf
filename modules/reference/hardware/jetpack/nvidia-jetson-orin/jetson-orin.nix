# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./jetson-orin.nix;

  options.ghaf.hardware.nvidia.orin = {
    # Enable the Orin boards
    enable = mkEnableOption "Orin hardware";

    flashScriptOverrides.onlyQSPI = mkEnableOption "to only flash QSPI partitions, i.e. disable flashing of boot and root partitions to eMMC";

    flashScriptOverrides.preFlashCommands = mkOption {
      description = "Commands to run before the actual flashing";
      type = types.str;
      default = "";
    };

    somType = mkOption {
      description = "SoM config Type (NX|AGX32|AGX64|Nano)";
      type = types.str;
      default = "agx";
    };

    carrierBoard = mkOption {
      description = "Board Type";
      type = types.str;
      default = "devkit";
    };

    kernelVersion = mkOption {
      description = "Kernel version";
      type = types.str;
      default = "bsp-default";
    };

    diskEncryption = {
      enable = mkEnableOption "generic LUKS root filesystem encryption for eMMC APP partition";

      mode = mkOption {
        description = "Disk encryption mode for Jetson root filesystem";
        type = types.enum [ "generic-luks-passphrase" ];
        default = "generic-luks-passphrase";
      };

      mapperName = mkOption {
        description = "Mapped device name used by initrd after LUKS unlock";
        type = types.str;
        default = "cryptroot";
      };
    };
  };

  config = mkIf cfg.enable {
    hardware.nvidia-jetpack.kernel.version = "${cfg.kernelVersion}";
    nixpkgs.hostPlatform.system = "aarch64-linux";

    ghaf.hardware = {
      aarch64.systemd-boot-dtb.enable = true;
      passthrough = {
        vhotplug.enable = true;
        usbQuirks.enable = true;
      };
    };

    boot = {
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      modprobeConfig.enable = true;

      kernelPatches = [
        {
          name = "vsock-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            VHOST = yes;
            VHOST_MENU = yes;
            VHOST_IOTLB = yes;
            VHOST_VSOCK = yes;
            VSOCKETS = yes;
            VSOCKETS_DIAG = yes;
            VSOCKETS_LOOPBACK = yes;
            VIRTIO_VSOCKETS_COMMON = yes;
          };
        }
      ]
      ++ lib.optionals (cfg.diskEncryption.enable && cfg.kernelVersion == "upstream-6-6") [
        {
          name = "dm-crypt-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            BLK_DEV_DM = yes;
            DM_BUFIO = yes;
            DM_BIO_PRISON = yes;
            DM_CRYPT = yes;
            CRYPTO_USER_API = yes;
            CRYPTO_USER_API_HASH = yes;
            CRYPTO_USER_API_SKCIPHER = yes;
            CRYPTO_XTS = yes;
          };
        }
      ];

    };

    boot.initrd = mkIf cfg.diskEncryption.enable {
      # Keep module selection aligned with the Orin JetPack baseline and avoid
      # requesting dm-crypt as a loadable module for upstream-6-6.
      availableKernelModules = lib.mkForce [
        "xhci-tegra"
        "ucsi_ccg"
        "typec_ucsi"
        "typec"
        "nvme"
        "tegra_mce"
        "phy-tegra-xusb"
        "i2c-tegra"
        "fusb301"
        "phy_tegra194_p2u"
        "pcie_tegra194"
        "nvpps"
        "nvethernet"
      ];
      kernelModules = lib.mkForce [ ];
      # algif_skcipher is not available with the upstream-6-6 kernel variant
      # used by current Orin reference targets.
      luks.cryptoModules = lib.mkForce [
        "aes"
        "aes_generic"
        "cbc"
        "xts"
        "sha1"
        "sha256"
        "sha512"
        "af_alg"
      ];
      luks.devices.${cfg.diskEncryption.mapperName} = {
        device = "/dev/mmcblk0p1";
        allowDiscards = true;
      };

      systemd.services."systemd-cryptsetup@${cfg.diskEncryption.mapperName}" = {
        overrideStrategy = "asDropin";
        unitConfig.After = [
          "initrd-root-device.target"
          "cryptsetup.target"
        ];
      };
    };

    fileSystems = mkIf cfg.diskEncryption.enable {
      "/" = lib.mkForce {
        device = "/dev/mapper/${cfg.diskEncryption.mapperName}";
        fsType = "ext4";
      };
    };

    services.nvpmodel = {
      enable = lib.mkDefault true;
      # Enable all CPU cores, full power consumption (50W on AGX, 25W on NX)
      profileNumber = lib.mkDefault 3;
    };
    hardware.deviceTree = {
      enable = lib.mkDefault true;
      # Add the include paths to build the dtb overlays
      dtboBuildExtraIncludePaths = [
        "${lib.getDev config.hardware.deviceTree.kernelPackage}/lib/modules/${config.hardware.deviceTree.kernelPackage.modDirVersion}/source/nvidia/soc/t23x/kernel-include"
      ];
    };

    # NOTE: "-nv.dtb" files are from NVIDIA's BSP
    # Versions of the device tree without PCI passthrough related
    # modifications.
  };
}
