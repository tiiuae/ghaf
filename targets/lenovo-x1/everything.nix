# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  microvm,
  lanzaboote,
  disko,
  name,
  system,
  ...
}: let
  # From here
  # These can be added back to default.nix to form part of the target template
  debugModules = import ./debugModules.nix;
  releaseModules = import ./releaseModules.nix;
  hwDefinition = import ./hardwareDefinition.nix;

  ## To here

  lenovo-x1 = variant: extraModules: let
    netvmExtraModules = [
      ({
          pkgs,
          config,
          ...
        }:
        #TODO convert these to modules when the lenovox1 module is created and imports these
        # also requires the hostConfiguration to be a module that can be imported
          import ./netvmExtraModules.nix {inherit lib config pkgs microvm hostConfiguration;})
    ];
    guivmExtraModules = [
      ({
          pkgs,
          config,
          ...
        }:
        #TODO convert these to modules when the lenovox1 module is created and imports these
        # also requires the hostConfiguration to be a module that can be imported
          import ./guivmExtraModules.nix {inherit lib config pkgs microvm hostConfiguration;})
    ];

    xdgPdfPort = 1200;

    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          lanzaboote.nixosModules.lanzaboote
          microvm.nixosModules.host
          disko.nixosModules.disko
          (import ../../modules/partitioning/lenovo-x1-disko-basic.nix {device = "/dev/nvme0n1";}) #TODO define device in hw def file
          ../../modules/partitioning/disko-basic-postboot.nix
          ../../modules/host
          ../../modules/virtualization/microvm/microvm-host.nix
          ../../modules/virtualization/microvm/netvm.nix
          ../../modules/virtualization/microvm/guivm.nix
          ../../modules/virtualization/microvm/appvm.nix
          ./sshkeys.nix
          ({
            pkgs,
            config,
            ...
          }: let
            powerControl = pkgs.callPackage ../../packages/powercontrol {};
          in {
            security.polkit.extraConfig = powerControl.polkitExtraConfig;

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

            environment.etc.${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = import ./getAuthKeysSource.nix {inherit pkgs config;};
            services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;

            ghaf = {
              hardware.definition = hwDefinition;
              # To enable guest hardening enable host hardening first
              host.kernel.hardening.enable = false;
              host.kernel.hardening.virtualization.enable = false;
              host.kernel.hardening.networking.enable = false;
              host.kernel.hardening.inputdevices.enable = false;

              guest.kernel.hardening.enable = false;
              guest.kernel.hardening.graphics.enable = false;

              host.kernel.hardening.hypervisor.enable = false;

              hardware.x86_64.common.enable = true;

              security.tpm2.enable = true;

              virtualization.microvm-host.enable = true;
              host.networking.enable = true;
              virtualization.microvm.netvm = {
                enable = true;
                extraModules = let
                  configH = config;
                  netvmPCIPassthroughModule = {
                    microvm.devices = lib.mkForce (
                      builtins.map (d: {
                        bus = "pci";
                        inherit (d) path;
                      })
                      configH.ghaf.hardware.definition.network.pciDevices
                    );
                  };
                in
                  [netvmPCIPassthroughModule]
                  ++ netvmExtraModules;
              };
              virtualization.microvm.guivm = {
                enable = true;
                extraModules = let
                  configH = config;
                  guivmPCIPassthroughModule = {
                    microvm.devices = lib.mkForce (
                      builtins.map (d: {
                        bus = "pci";
                        inherit (d) path;
                      })
                      configH.ghaf.hardware.definition.gpu.pciDevices
                    );
                  };
                  guivmVirtioInputHostEvdevModule = {
                    microvm.qemu.extraArgs =
                      builtins.concatMap (d: [
                        "-device"
                        "virtio-input-host-pci,evdev=${d}"
                      ])
                      configH.ghaf.hardware.definition.virtioInputHostEvdevs;
                  };
                in
                  [
                    guivmPCIPassthroughModule
                    guivmVirtioInputHostEvdevModule
                  ]
                  ++ guivmExtraModules;
              };
              virtualization.microvm.appvm = {
                enable = true;
                vms = [
                  {
                    name = "chromium";
                    packages = let
                      # PDF XDG handler is executed when the user opens a PDF file in the browser
                      # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
                      xdgPdfItem = pkgs.makeDesktopItem {
                        name = "ghaf-pdf";
                        desktopName = "Ghaf PDF handler";
                        exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
                        mimeTypes = ["application/pdf"];
                      };
                      xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
                        filepath=$(realpath $1)
                        echo "Opening $filepath" | systemd-cat -p info
                        echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm.ghaf ${toString xdgPdfPort}
                      '';
                    in [
                      pkgs.chromium
                      pkgs.pamixer
                      pkgs.xdg-utils
                      xdgPdfItem
                      xdgOpenPdf
                    ];
                    macAddress = "02:00:00:03:05:01";
                    ramMb = 3072;
                    cores = 4;
                    extraModules = [
                      {
                        # Enable pulseaudio for user ghaf
                        sound.enable = true;
                        hardware.pulseaudio.enable = true;
                        users.extraUsers.ghaf.extraGroups = ["audio"];

                        time.timeZone = "Asia/Dubai";

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

                        # Disable chromium built-in PDF viewer to make it execute xdg-open
                        programs.chromium.enable = true;
                        programs.chromium.extraOpts."AlwaysOpenPdfExternally" = true;
                        # Set default PDF XDG handler
                        xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";
                      }
                    ];
                    borderColor = "#ff5733";
                  }
                  {
                    name = "gala";
                    packages = [pkgs.gala-app];
                    macAddress = "02:00:00:03:06:01";
                    ramMb = 1536;
                    cores = 2;
                    extraModules = [
                      {
                        time.timeZone = "Asia/Dubai";
                      }
                    ];
                    borderColor = "#33ff57";
                  }
                  {
                    name = "zathura";
                    packages = [pkgs.zathura];
                    macAddress = "02:00:00:03:07:01";
                    ramMb = 512;
                    cores = 1;
                    extraModules = [
                      {
                        time.timeZone = "Asia/Dubai";
                      }
                    ];
                    borderColor = "#337aff";
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

          #TODO: how to handle the majority of laptops that need a little
          # something extra?
          # SEE: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
          # nixos-hardware.nixosModules.lenovo-thinkpad-x1-10th-gen

          ({config, ...}: {
            boot.kernelParams = let
              filterDevices = builtins.filter (d: d.vendorId != null && d.productId != null);
              mapPciIdsToString = builtins.map (d: "${d.vendorId}:${d.productId}");
              vfioPciIds = mapPciIdsToString (filterDevices (
                config.ghaf.hardware.definition.network.pciDevices
                ++ config.ghaf.hardware.definition.gpu.pciDevices
              ));
            in [
              "intel_iommu=on,igx_off,sm_on"
              "iommu=pt"
              # Prevent i915 module from being accidentally used by host
              "module_blacklist=i915"

              "vfio-pci.ids=${builtins.concatStringsSep "," vfioPciIds}"
            ];

            boot.initrd.availableKernelModules = ["nvme"];
          })
        ]
        ++ (import ../../modules/module-list.nix)
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.diskoImages;
  };
in [
  (lenovo-x1 "debug" debugModules)
  (lenovo-x1 "release" releaseModules)
]
