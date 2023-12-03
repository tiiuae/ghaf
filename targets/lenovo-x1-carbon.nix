# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  lib,
  inputs,
  ...
}: let
  inherit (inputs) nixos-generators microvm lanzaboote config;
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;

  # TODO break this out into its own module
  hwDefinition = {
    name = "Lenovo X1 Carbon";
    network.pciDevices = [
      # Passthrough Intel WiFi card 8086:51f1
      {
        path = "0000:00:14.3";
        vendorId = "8086";
        productId = "51f1";
      }
    ];
    gpu.pciDevices = [
      # Passthrough Intel Iris GPU 8086:a7a1
      {
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "a7a1";
      }
    ];
    virtioInputHostEvdevs = [
      # Lenovo X1 touchpad and keyboard
      "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
      "/dev/mouse"
      "/dev/touchpad"
      # Lenovo X1 trackpoint (red button/joystick)
      "/dev/input/by-path/platform-i8042-serio-1-event-mouse"
    ];
  };
  lenovo-x1 = variant: extraModules: let
    # TODO move all the ExtraModules out to separate place
    netvmExtraModules = [
      ({pkgs, ...}: {
        microvm = {
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
        # TODO Figure out where all this should live
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
        # Add simple wi-fi connection helper
        environment.systemPackages = lib.mkIf hostConfiguration.config.ghaf.profiles.debug.enable [pkgs.wifi-connector-nmcli];
        services.openssh = {
          authorizedKeysCommand = "/etc/ssh/get-auth-keys";
          authorizedKeysCommandUser = "nobody";
        };
      })
    ];
    # TODO put this behind not HostOSOnly flags
    guivmConfig = hostConfiguration.config.ghaf.virtualization.microvm.guivm;
    winConfig = hostConfiguration.config.ghaf.windows-launcher;
    guivmExtraModules = [
      {
        # Early KMS needed for GNOME to work inside GuiVM
        boot.initrd.kernelModules = ["i915"];
        microvm.qemu.extraArgs = [
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
      }
    ]; # TODO Filthy dirty, need to invoke the nixosModules as next clean
    #++ [(hostConfiguration.config.ghaf.graphics.weston.launchers)];

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
          ({
            pkgs,
            config,
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
              hardware.definition = hwDefinition;
              host.kernel_hardening.enable = false;

              host.hypervisor_hardening.enable = false;

              hardware.x86_64.common.enable = true;

              profiles.graphics.enable = true;
              graphics.displayManager = "weston";

              virtualization.microvm-host.enable = true;
              host.networking.enable = true;

              # TODO Move the VM initializations to own modules
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
              };

              # TODO Specifically Enable the apps
              # Chrome
              # Gala
              # Zathura
              # Enable all the default UI applications
              profiles = {
                applications.enable = false;
              };

              # TODO Fix where to do the setup and config of this
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
  # TODO move Gnome to its own module repo
  #gnomeModules = [{ghaf.virtualization.microvm.guivm.extraModules = [{ghaf.profiles.graphics.compositor = "gnome";}];}];
  targets = [
    (lenovo-x1 "debug" debugModules)
    (lenovo-x1 "release" releaseModules)
    # (lenovo-x1 "gnome-debug" (gnomeModules ++ debugModules))
    # (lenovo-x1 "gnome-release" (gnomeModules ++ releaseModules))
  ];
in {
  flake.nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  flake.packages = {
    x86_64-linux =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
