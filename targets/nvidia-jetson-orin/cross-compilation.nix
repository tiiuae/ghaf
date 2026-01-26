# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Cross-compilation module
#
{ config, lib, ... }:
let
  jetpackFlashInitrdOverlay =
    _final: prev:
    let
      cfg = config.hardware.nvidia-jetpack;
    in
    lib.optionalAttrs (cfg.enable or false) {
      nvidia-jetpack = prev.nvidia-jetpack.overrideScope (
        finalJetpack: _prevJetpack: {
          flashInitrd =
            let
              spiModules =
                if lib.versions.majorMinor config.system.build.kernel.version == "5.10" then
                  [
                    "qspi_mtd"
                    "spi_tegra210_qspi"
                    "at24"
                    "spi_nor"
                  ]
                else
                  [
                    "mtdblock"
                    "spi_tegra210_quad"
                  ];
              usbModules =
                if lib.versions.majorMinor config.system.build.kernel.version == "5.10" then
                  [ ]
                else
                  [
                    "libcomposite"
                    "udc-core"
                    "tegra-xudc"
                    "xhci-tegra"
                    "u_serial"
                    "usb_f_acm"
                  ];
              modules = spiModules ++ usbModules ++ cfg.flashScriptOverrides.additionalInitrdFlashModules;
              modulesClosure = prev.makeModulesClosure {
                rootModules = modules;
                kernel = config.system.modulesTree;
                inherit (config.hardware) firmware;
                allowMissing = false;
              };
              manufacturer = "NixOS";
              product = "serial";
              serialnumber = "0";
              jetpack-init = prev.writeScript "init" ''
                #!${prev.pkgsStatic.busybox}/bin/sh
                export PATH=${prev.pkgsStatic.busybox}/bin
                mkdir -p /proc /dev /sys
                mount -t proc proc -o nosuid,nodev,noexec /proc
                mount -t devtmpfs none -o nosuid /dev
                mount -t sysfs sysfs -o nosuid,nodev,noexec /sys
                ln -s /proc/self/fd /dev/ # for >(...) support

                for mod in ${toString modules}; do
                  modprobe -v $mod
                done

                mount -t configfs none /sys/kernel/config
                if [ -e /sys/kernel/config/usb_gadget ] ; then
                  # https://origin.kernel.org/doc/html/v5.10/usb/gadget_configfs.html
                  gadget=/sys/kernel/config/usb_gadget/g.1
                  mkdir $gadget

                  echo 0x1d6b >$gadget/idVendor # Linux Foundation
                  echo 0x104 >$gadget/idProduct # Multifunction Composite Gadget

                  mkdir $gadget/strings/0x409
                  echo ${manufacturer} >$gadget/strings/0x409/manufacturer
                  echo ${product} >$gadget/strings/0x409/product
                  echo ${serialnumber} >$gadget/strings/0x409/serialnumber

                  mkdir $gadget/configs/c.1
                  mkdir $gadget/functions/acm.usb0

                  ln -s $gadget/functions/acm.usb0 $gadget/configs/c.1/

                  echo "$(ls /sys/class/udc | head -n 1)" >$gadget/UDC

                  # force into device mode if OTG and something is up with automatic detection
                  if [ -w /sys/class/usb_role/usb2-0-role-switch/role ] ; then
                    echo device > /sys/class/usb_role/usb2-0-role-switch/role
                  fi

                  sleep 5  # The configuration doesn't happen synchronously and takes >1 sec. 5 seconds seems like a good buffer and also gives time for host to connect
                  mdev -s

                  ttyGS=/dev/ttyGS$(cat $gadget/functions/acm.usb0/port_num)
                  if [ -e $ttyGS ]; then
                    exec &> >(tee $ttyGS) <$ttyGS
                  fi
                fi

                # `signedFirmware` must be built on x86_64, so we make a
                # concatenated initrd that places `signedFirmware` at a well
                # known path so that the final initrd can be constructed from
                # outside the context of this nixos config (which has an
                # aarch64-linux package-set).
                if ${lib.getExe finalJetpack.flashFromDevice} ${finalJetpack.signedFirmware}; then
                  echo "Flashing platform firmware successful. Rebooting now."
                  sync
                  reboot -f
                else
                  echo "Flashing platform firmware unsuccessful."
                  ${lib.optionalString (cfg.firmware.secureBoot.pkcFile == null) ''
                    echo "Entering console"
                    exec ${prev.pkgsStatic.busybox}/bin/sh
                  ''}
                fi
              '';
            in
            (prev.makeInitrd {
              contents = [
                {
                  object = jetpack-init;
                  symlink = "/init";
                }
                {
                  object = modulesClosure;
                  symlink = "/lib";
                  suffix = "/lib";
                }
              ];
            }).overrideAttrs
              (prevAttrs: {
                passthru = prevAttrs.passthru // {
                  inherit manufacturer product serialnumber;
                };
              });
        }
      );
    };
in
{
  nixpkgs = {
    #TODO: move this to the targets dir and call this from the cross-targets
    #section under the -from-x86_64 section
    buildPlatform.system = "x86_64-linux";
    overlays = [
      (import ../../overlays/cross-compilation)
      jetpackFlashInitrdOverlay
    ];
  };
}
