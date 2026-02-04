# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.uarti_net_vm;

  # Derivation to build the GPU-VM guest device tree
  netvm-dtb = pkgs.stdenv.mkDerivation {
    name = "netvm-dtb";
    phases = [
      "unpackPhase"
      "buildPhase"
      "installPhase"
    ];
    src = ./tegra234-netvm.dts;
    nativeBuildInputs = with pkgs; [
      dtc
    ];
    unpackPhase = ''
      cp $src ./tegra234-netvm.dts
    '';
    buildPhase = ''
      $CC -E -nostdinc \
        -I${config.boot.kernelPackages.nvidia-modules.src}/hardware/nvidia/t23x/nv-public/include/nvidia-oot \
        -I${config.boot.kernelPackages.nvidia-modules.src}/hardware/nvidia/t23x/nv-public/include/kernel \
        -undef -D__DTS__ \
        -x assembler-with-cpp \
        tegra234-netvm.dts > preprocessed.dts
      dtc -I dts -O dtb -o tegra234-netvm.dtb preprocessed.dts
    '';
    installPhase = ''
      mkdir -p $out
      cp tegra234-netvm.dtb $out/
    '';
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.uarti_net_vm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable UARTI passthrough on Nvidia Orin to the Net-VM";
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      # Make group kvm all devices that bind to vfio in iommu group 59
      SUBSYSTEM=="vfio",GROUP="kvm"
    '';
    ghaf.hardware.nvidia.virtualization.enable = true;

    # Passthrough devices - use hardware.definition for composition model
    ghaf.hardware.definition.netvm.extraModules = [
      {
        # Use serial passthrough (ttyAMA0) and virtual PCI serial (ttyS0)
        # as Linux console
        microvm = {
          kernelParams = [ "console=ttyAMA0 console=ttyS0" ];
          qemu = {
            serialConsole = false;
            extraArgs = [
              # Add custom dtb to Net-VM with 31d0000.serial in platform devices
              "-dtb"
              "${netvm-dtb.out}/tegra234-netvm.dtb"
              # Add UARTI (31d0000.serial) as passtrhough device
              "-device"
              "vfio-platform,host=31d0000.serial"
              # Add a virtual PCI serial device as console
              "-device"
              "pci-serial,chardev=stdio,id=serial0"
            ];
          };
        };
      }
    ];

    # Make sure that Net-VM runs after the binding services are enabled
    systemd.services."microvm@net-vm".after = [ "bindSerial31d0000.service" ];

    systemd.services.bindSerial31d0000 = {
      description = "Bind UARTI to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = ''
          ${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/31d0000.serial/driver_override"
        '';
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c "echo 31d0000.serial > /sys/bus/platform/drivers/vfio-platform/bind"
        '';
      };
    };

    # Enable hardware.deviceTree for handle host dtb overlays
    hardware.deviceTree.enable = true;

    hardware.deviceTree.overlays = [
      {
        name = "uarti_pt_host_overlay";
        dtsFile = ./uarti_pt_host_overlay.dts;
      }
    ];
  };
}
