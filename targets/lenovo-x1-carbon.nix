# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  self,
  lib,
  nixos-generators,
  nixos-hardware,
  microvm,
}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;
  lenovo-x1 = variant: extraModules: let
    netvmExtraModules = [
      {
        microvm.devices = lib.mkForce [
          {
            bus = "pci";
            path = "0000:00:14.3";
          }
        ];

        # For WLAN firmwares
        hardware.enableRedistributableFirmware = true;

        networking.wireless = {
          enable = true;

          #networks."ssid".psk = "psk";
        };
      }
    ];
    guivmExtraModules = [
      {
        microvm.qemu.extraArgs = [
          # Lenovo X1 touchpad and keyboard
          "-device"
          "virtio-input-host-pci,evdev=/dev/input/by-path/platform-i8042-serio-0-event-kbd"
          "-device"
          "virtio-input-host-pci,evdev=/dev/mouse"
          "-device"
          "virtio-input-host-pci,evdev=/dev/touchpad"
          # Lenovo X1 trackpoint (red button/joystick)
          "-device"
          "virtio-input-host-pci,evdev=/dev/input/by-path/platform-i8042-serio-1-event-mouse"
          # Lenovo X1 Lid button
          "-device"
          "button"
          # Lenovo X1 battery
          "-device"
          "battery"
          # Lenovo X1 AC adapter
          "-device"
          "acad"
        ];
        microvm.devices = [
          {
            bus = "pci";
            path = "0000:00:02.0";
          }
        ];
      }
      ({pkgs, ...}: {
        ghaf.graphics.weston.launchers = [
          {
            path = "${pkgs.waypipe}/bin/waypipe ssh -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.5 chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
            icon = "${pkgs.weston}/share/weston/icon_editor.png";
          }

          {
            path = "${pkgs.waypipe}/bin/waypipe ssh -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.6 gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
            icon = "${pkgs.weston}/share/weston/icon_editor.png";
          }

          {
            path = "${pkgs.waypipe}/bin/waypipe ssh -i ${pkgs.waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.7 zathura";
            icon = "${pkgs.weston}/share/weston/icon_editor.png";
          }
        ];
      })
    ];
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          microvm.nixosModules.host
          ../modules/host
          ../modules/virtualization/microvm/microvm-host.nix
          ../modules/virtualization/microvm/netvm.nix
          ../modules/virtualization/microvm/guivm.nix
          ../modules/virtualization/microvm/appvm.nix
          ({
            pkgs,
            lib,
            ...
          }: {
            services.udev.extraRules = ''
              # Laptop keyboard
              SUBSYSTEM=="input",ATTRS{name}=="AT Translated Set 2 keyboard",GROUP="kvm"
              # Laptop touchpad
              SUBSYSTEM=="input",ATTRS{name}=="SYNA8016:00 06CB:CEB3 Mouse",KERNEL=="event*",GROUP="kvm",SYMLINK+="mouse"
              SUBSYSTEM=="input",ATTRS{name}=="SYNA8016:00 06CB:CEB3 Touchpad",KERNEL=="event*",GROUP="kvm",SYMLINK+="touchpad"
              # Laptop touchpad - UAE revision
              SUBSYSTEM=="input",ATTRS{name}=="ELAN067C:00 04F3:31F9 Mouse",KERNEL=="event*",GROUP="kvm",SYMLINK+="mouse"
              SUBSYSTEM=="input",ATTRS{name}=="ELAN067C:00 04F3:31F9 Touchpad",KERNEL=="event*",GROUP="kvm",SYMLINK+="touchpad"
              # Laptop TrackPoint
              SUBSYSTEM=="input",ATTRS{name}=="TPPS/2 Elan TrackPoint",GROUP="kvm"
              # Lenovo X1 integrated webcam
              SUBSYSTEM=="usb", ATTR{idVendor}=="04f2", ATTR{idProduct}=="b751", GROUP="kvm"
            '';

            # Enable pulseaudio support for host as a service
            sound.enable = true;
            hardware.pulseaudio.enable = true;
            hardware.pulseaudio.systemWide = true;
            nixpkgs.config.pulseaudio = true;

            # Allow microvm user to access pulseaudio
            hardware.pulseaudio.extraConfig = "load-module module-combine-sink module-native-protocol-unix auth-anonymous=1";
            users.extraUsers.microvm.extraGroups = ["audio" "pulse-access"];

            ghaf = {
              hardware.x86_64.common.enable = true;

              virtualization.microvm-host.enable = true;
              host.networking.enable = true;
              virtualization.microvm.netvm = {
                enable = true;
                extraModules = netvmExtraModules;
              };
              virtualization.microvm.guivm = {
                enable = true;
                extraModules = guivmExtraModules;
              };
              virtualization.microvm.appvm = {
                enable = true;
                vms = [
                  {
                    name = "chromium";
                    packages = [pkgs.chromium pkgs.pamixer];
                    ipAddress = "192.168.101.5/24";
                    macAddress = "02:00:00:03:05:01";
                    ramMb = 3072;
                    cores = 4;
                    extraModules = [
                      {
                        # Enable pulseaudio for user ghaf
                        sound.enable = true;
                        hardware.pulseaudio.enable = true;
                        users.extraUsers.ghaf.extraGroups = ["audio"];
                        nixpkgs.config.pulseaudio = true;

                        microvm.qemu.extraArgs = [
                          # APPVMs use microvm qemu machine which has pcie disabled by default
                          "-M"
                          "microvm,pcie=on,accel=kvm:tcg,pit=off,pic=off,rtc=off,mem-merge=on"
                          # Lenovo X1 integrated usb webcam
                          "-device"
                          "qemu-xhci"
                          "-device"
                          "usb-host,vendorid=0x04f2,productid=0xb751"
                          # Connect sound device to hosts pulseaudio socket
                          "-audiodev"
                          "pa,id=pa1,server=unix:/run/pulse/native"
                          # Add HDA sound device to guest
                          "-device"
                          "intel-hda"
                          "-device"
                          "hda-duplex,audiodev=pa1"
                        ];
                        microvm.devices = [];
                      }
                    ];
                  }
                  {
                    name = "gala";
                    packages = [pkgs.gala-app];
                    ipAddress = "192.168.101.6/24";
                    macAddress = "02:00:00:03:06:01";
                    ramMb = 1536;
                    cores = 2;
                  }
                  {
                    name = "zathura";
                    packages = [pkgs.zathura];
                    ipAddress = "192.168.101.7/24";
                    macAddress = "02:00:00:03:07:01";
                    ramMb = 512;
                    cores = 1;
                  }
                ];
                extraModules = [
                  ../overlays/custom-packages.nix
                ];
              };

              # Enable all the default UI applications
              profiles = {
                applications.enable = false;
                #TODO clean this up when the microvm is updated to latest
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              windows-launcher.enable = false;
            };
          })

          formatModule

          #TODO: how to handle the majority of laptops that need a little
          # something extra?
          # SEE: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
          # nixos-hardware.nixosModules.lenovo-thinkpad-x1-10th-gen

          {
            boot.kernelParams = [
              "intel_iommu=on,igx_off,sm_on"
              "iommu=pt"

              # Passthrough Intel WiFi card 8086:51f1
              # Passthrough Intel Iris GPU 8086:a7a1
              "vfio-pci.ids=8086:51f1,8086:a7a1"
            ];
          }
        ]
        ++ (import ../modules/module-list.nix)
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  debugModules = [../modules/development/usb-serial.nix {ghaf.development.usb-serial.enable = true;}];
  targets = [
    (lenovo-x1 "debug" debugModules)
    (lenovo-x1 "release" [])
  ];
in {
  nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  packages = {
    x86_64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
