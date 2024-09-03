# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ lib, pkgs, config, ... }: let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpio_vm;

  kernelPath = "${config.system.build.kernel}";
  guestKernel = "${kernelPath}/Image"; # the host's kernel image can be used in the guest

  dtsName = "qemu-gpio-guestvm.dts";
  dtbName = "qemu-gpio-guestvm.dtb";

  # Build the guest specific DTB file for GPIO passthrough
  gpioDtbDerivation = builtins.trace "Creating guest DTB" pkgs.stdenv.mkDerivation {
    pname = "gpio-vm-dtb";
    version = "1.0";

    src = ./dtb;
    buildInputs = [ pkgs.dtc ];

    # unpackPhase = ''
    #   mkdir -p ${kernelPath}/dtbs
    #   cp ${dtsName} ${kernelPath}/dtbs/
    # '';

    buildPhase = ''
      mkdir -p $out
      # ls -thog $src
      dtc -I dts -O dtb -o $out/${dtbName} $src/${dtsName}
      # ls -thog $out
    '';

    installPhase = ''
      # cp $src/${dtsName} ${kernelPath}/dtbs/
      # cp $out/${dtbName} ${kernelPath}/dtbs/
    '';
   
    outputs = [ "out" ];
  };

  gpioGuestDtb = "${gpioDtbDerivation}/${dtbName}";

  /*
  guestRootFsName = "gpiovm_rootfs.qcow2";   # a non-ghaf temporary fs for debugging
  # Create the guest rootfs qcow2 file (not a ghaf fs -- temporary)
  gpioGuestFsDerivation = builtins.trace "Creating guest rootfs" pkgs.stdenv.mkDerivation {
    pname = "gpio-guest-fs";
    version = "1.0";

    buildInputs = [ pkgs.bzip2 ];

    src = ./qcow2;
    
    buildPhase = ''
      echo buildPhase
      # ls -thog $src

      mkdir -p $out 
      if [ -f $src/${guestRootFsName}.x00 ]
        then
          echo "split qcow2 in source"
          cat $src/${guestRootFsName}.x* >> $out/${guestRootFsName}
        else if [ -f $src/${guestRootFsName}.bzip2.x00 ]
          then 
            echo "split bzip2 in source"
            cat $src/${guestRootFsName}.bzip2.x* | \
            bunzip2 -dc > $out/${guestRootFsName}
          fi  
        fi
      echo "target created"
    '';

    installPhase = ''
    '';

    rootFs = "$out/${guestRootFsName}";
    # outputs = [ "rootFs" ];
    outputs = [ "out" ];
  };

  guestRootFs = "${gpioGuestFsDerivation}/${guestRootFsName}";
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
    builtins.trace "GpioVM: ghaf.virtualization.microvm.gpiovm.extraModules"
    [
      {
        microvm = {
          kernelParams = [
            "rootwait root=/dev/vda"
          ];
          graphics.enable = false;
          qemu = {
          # qemu = builtins.trace "Qemu params, filenames: ${dtsName}, ${dtbName}, ${guestKernel}, ${guestRootFsName}" {
            serialConsole = true;
            extraArgs = lib.mkForce [
            # extraArgs = builtins.trace "GpioVM: Evaluating qemu.extraArgs for gpio-vm" [
              "-sandbox" "on"
              "-nographic"
              "-no-reboot"
              "-dtb" "${gpioGuestDtb}"
              "-kernel" "${guestKernel}"
              # "-drive" "file=${guestRootFs},if=virtio,format=qcow2"
              "-machine" "virt,accel=kvm"
              "-cpu" "host"
              "-m" "2G"
              "-smp" "2"
              "-serial" "pty"
              # "-net" "user,hostfwd=tcp::2222-:22"
              # "-net" "nic"
            ];
          };
        };
      }
    ];
  };
}
