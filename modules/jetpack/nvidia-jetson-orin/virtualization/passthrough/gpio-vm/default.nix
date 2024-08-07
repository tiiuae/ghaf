# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ lib, pkgs, config, ... }: let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpio_vm;

  # dtsName = "qemu-gpio-guestvm.dts";
  # dtbName = "qemu-gpio-guestvm.dtb";
  kernelPath = "${config.system.build.kernel}";
  guestRootfs = ./gpiovm_rootfs.qcow2;   # a non-ghaf temporary fs for debugging
  guestKernel = "${kernelPath}/Image"; # the host's kernel image can be used in the guest

  /*
  # Define the custom derivation to build the DTB file
  gpioDtbDerivation = pkgs.stdenv.mkDerivation {
    pname = "gpio-vm-dtb";
    version = "1.0";

    src = ./.;
    buildInputs = [ pkgs.dtc ];

    # unpackPhase = ''
    #   mkdir -p ${kernelPath}/dtbs
    #   cp ${dtsName} ${kernelPath}/dtbs/
    # '';

    buildPhase = builtins.trace "Building guest DTB"  ''
      # mkdir -p $out
      # dtc -I dts -O dtb -o $out/${dtbName} $src/${dtsName}
      dtc -I dts -O dtb -o ${dtbName} ${dtsName}
    '';

    # installPhase = builtins.trace "Copying built guest DTB" ''
    #   mkdir -p $out
    #   cp ${dtbName} $out/${dtbName}
    # '';
    
    # outputs = [ "${kernelPath}/dtbs/${dtsName}" "$out/${dtbName}" ];
    outputs = [ "${dtsName}" "${dtbName}" ];
  };
  */
in {
  options = {
    ghaf.hardware.nvidia.passthroughs.gpio_vm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GPIO passthrough on Nvidia Orin to the Gpio-VM";
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization.enable = true;

    ghaf.virtualization.microvm.gpiovm.extraModules =
    builtins.trace "GpioVM: (in default.nix) ghaf.virtualization.microvm.gpiovm.extraModules"
    [
      {
        microvm = {
          kernelParams = [
            "rootwait root=/dev/vda console=ttyS3"
          ];
          graphics.enable = false;
          # qemu = builtins.trace "Qemu params, filenames: ${dtsName}, ${dtbName}, ${guestKernel}, ${guestRootfs}" {
          qemu = {
            serialConsole = false;
            extraArgs = builtins.trace "GpioVM: Evaluating qemu.extraArgs for gpio-vm" [
              "-nographic"
              "-no-reboot"
              # "-dtb ${gpioGuestDtbName}"  
              # "-dtb ${dtbName}"  
              "-kernel ${guestKernel}"
              "-machine virt,accel=kvm"
              "-cpu host"
              "-m 2G"
              "-smp 2"
              "-drive file=${guestRootfs},if=virtio,format=qcow2"
              "-serial /dev/ttyS3"
              "-net user,hostfwd=tcp::2222-:22 -net nic"
              "-monitor chardev=ttyTHS2,mode=readline"
              # "-append rootwait \"root=/dev/vda console=ttyS3\""
            ];
          };
        };
      }
    ];

    boot.kernelPatches = [
      {
        name = "In Gpio-VM add device tree with VDA for host";
        patch = builtins.trace "patch: gpio_vm_dtb_with_vda.patch" ./patches/gpio_vm_dtb_with_vda.patch;
      }
    ];
  };
}
