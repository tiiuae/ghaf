# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  lib,
  nixos-generators,
  microvm,
  lanzaboote,
  ...
}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;
  lenovo-x1 = variant: extraModules: let
    netvmExtraModules = [
      ({pkgs, ...}: {
        microvm = {
          devices = lib.mkForce [
            {
              bus = "pci";
              path = "0000:00:14.3";
            }
          ];
          shares = [
            {
              tag = "waypipe-ssh-public-key";
              source = "/run/waypipe-ssh-public-key";
              mountPoint = "/run/waypipe-ssh-public-key";
            }
          ];
        };
        fileSystems."/run/waypipe-ssh-public-key".options = ["ro"];

        # For WLAN firmwares
        hardware.enableRedistributableFirmware = true;

        networking = {
          # wireless is disabled because we use NetworkManager for wireless
          wireless.enable = false;
          networkmanager = {
            enable = true;
            unmanaged = ["ethint0"];
          };
        };
        # noXlibs=false; needed for NetworkManager stuff
        environment.noXlibs = false;
        environment.etc."NetworkManager/system-connections/Wifi-1.nmconnection" = {
          text = ''
            [connection]
            id=Wifi-1
            uuid=33679db6-4cde-11ee-be56-0242ac120002
            type=wifi
            [wifi]
            mode=infrastructure
            ssid=SSID_OF_NETWORK
            [wifi-security]
            key-mgmt=wpa-psk
            psk=WPA_PASSWORD
            [ipv4]
            method=auto
            [ipv6]
            method=disabled
            [proxy]
          '';
          mode = "0600";
        };

        # Waypipe-ssh key is used here to create keys for ssh tunneling to forward D-Bus sockets.
        # SSH is very picky about to file permissions and ownership and will
        # accept neither direct path inside /nix/store or symlink that points
        # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
        # setting mode), instead of symlinking it.
        environment.etc."ssh/get-auth-keys" = {
          source = let
            script = pkgs.writeShellScriptBin "get-auth-keys" ''
              [[ "$1" != "ghaf" ]] && exit 0
              ${pkgs.coreutils}/bin/cat /run/waypipe-ssh-public-key/id_ed25519.pub
            '';
          in "${script}/bin/get-auth-keys";
          mode = "0555";
        };
        services.openssh = {
          authorizedKeysCommand = "/etc/ssh/get-auth-keys";
          authorizedKeysCommandUser = "nobody";
        };
      })
    ];
    guivmConfig = hostConfiguration.config.ghaf.virtualization.microvm.guivm;
    winConfig = hostConfiguration.config.ghaf.windows-launcher;
    guivmExtraModules = [
      {
        # Early KMS needed for GNOME to work inside GuiVM
        boot.initrd.kernelModules = ["i915"];

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
            path = "${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no chromium-vm.ghaf ${pkgs.waypipe}/bin/waypipe --border \"#ff5733,5\" --vsock -s ${toString guivmConfig.waypipePort} server chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
            icon = "${../assets/icons/png/browser.png}";
          }

          {
            path = "${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no gala-vm.ghaf ${pkgs.waypipe}/bin/waypipe --border \"#33ff57,5\" --vsock -s ${toString guivmConfig.waypipePort} server gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
            icon = "${../assets/icons/png/app.png}";
          }

          {
            path = "${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no zathura-vm.ghaf ${pkgs.waypipe}/bin/waypipe --border \"#337aff,5\" --vsock -s ${toString guivmConfig.waypipePort} server zathura";
            icon = "${../assets/icons/png/pdf.png}";
          }

          {
            path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
            icon = "${../assets/icons/png/windows.png}";
          }

          {
            path = "${pkgs.nm-launcher}/bin/nm-launcher";
            icon = "${pkgs.networkmanagerapplet}/share/icons/hicolor/22x22/apps/nm-device-wwan.png";
          }
        ];
      })
    ];
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          lanzaboote.nixosModules.lanzaboote
          microvm.nixosModules.host
          ../modules/host
          ../modules/virtualization/microvm/microvm-host.nix
          ../modules/virtualization/microvm/netvm.nix
          ../modules/virtualization/microvm/guivm.nix
          ../modules/virtualization/microvm/appvm.nix
          ({pkgs, ...}: {
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

            time.timeZone = "Asia/Dubai";

            # Enable pulseaudio support for host as a service
            sound.enable = true;
            hardware.pulseaudio.enable = true;
            hardware.pulseaudio.systemWide = true;
            # Add systemd to require pulseaudio before starting chromium-vm
            systemd.services."microvm@chromium-vm".after = ["pulseaudio.service"];
            systemd.services."microvm@chromium-vm".requires = ["pulseaudio.service"];

            # Allow microvm user to access pulseaudio
            hardware.pulseaudio.extraConfig = "load-module module-combine-sink module-native-protocol-unix auth-anonymous=1";
            users.extraUsers.microvm.extraGroups = ["audio" "pulse-access"];

            ghaf = {
              host.kernel_hardening.enable = false;

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
                    macAddress = "02:00:00:03:05:01";
                    ramMb = 3072;
                    cores = 4;
                    extraModules = [
                      {
                        # Enable pulseaudio for user ghaf
                        sound.enable = true;
                        hardware.pulseaudio.enable = true;
                        users.extraUsers.ghaf.extraGroups = ["audio"];

                        microvm.qemu.extraArgs = [
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
                    macAddress = "02:00:00:03:06:01";
                    ramMb = 1536;
                    cores = 2;
                  }
                  {
                    name = "zathura";
                    packages = [pkgs.zathura];
                    macAddress = "02:00:00:03:07:01";
                    ramMb = 512;
                    cores = 1;
                  }
                ];
              };

              # Enable all the default UI applications
              profiles = {
                applications.enable = false;
              };
              windows-launcher = {
                enable = true;
                spice = true;
              };
            };
          })

          ({config, ...}: {
            ghaf.installer = {
              enable = true;
              imgModules = [
                nixos-generators.nixosModules.raw-efi
              ];
              enabledModules = ["flushImage"];
              installerCode = ''
                echo "Starting flushing..."
                if sudo dd if=${config.system.build.${config.formatAttr}}/nixos.img of=/dev/${config.ghaf.installer.installerModules.flushImage.providedVariables.deviceName} conv=sync bs=4K status=progress; then
                    sync
                    echo "Flushing finished successfully!"
                    echo "Now you can detach installation device and reboot to ghaf."
                else
                    echo "Some error occured during flushing process, exit code: $?."
                    exit
                fi
              '';
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
              # Prevent i915 module from being accidentally used by host
              "module_blacklist=i915"

              # Passthrough Intel WiFi card 8086:51f1
              # Passthrough Intel Iris GPU 8086:a7a1
              "vfio-pci.ids=8086:51f1,8086:a7a1"
            ];
            boot.initrd.availableKernelModules = ["nvme"];
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
  debugModules = [
    ../modules/development/usb-serial.nix
    {
      ghaf.development.usb-serial.enable = true;
      ghaf.profiles.debug.enable = true;
    }
    ../modules/host/secureboot.nix
    {
      ghaf.host.secureboot.enable = false;
    }
  ];
  releaseModules = [
    {
      ghaf.profiles.release.enable = true;
    }
  ];
  gnomeModules = [{ghaf.virtualization.microvm.guivm.extraModules = [{ghaf.profiles.graphics.compositor = "gnome";}];}];
  targets = [
    (lenovo-x1 "debug" debugModules)
    (lenovo-x1 "release" releaseModules)
    (lenovo-x1 "gnome-debug" (gnomeModules ++ debugModules))
    (lenovo-x1 "gnome-release" (gnomeModules ++ releaseModules))
  ];
in {
  flake.nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  flake.packages = {
    x86_64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
