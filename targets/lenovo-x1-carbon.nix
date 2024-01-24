# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  lib,
  nixos-generators,
  microvm,
  lanzaboote,
  nixpkgs,
  disko,
  ...
}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;

  powerControlPkgPath = ../packages/powercontrol;

  getAuthKeysFileName = "get-auth-keys";
  getAuthKeysFilePathInEtc = "ssh/${getAuthKeysFileName}";

  waypipeSshPublicKeyName = "waypipe-ssh-public-key";
  waypipeSshPublicKeyDir = "/run/${waypipeSshPublicKeyName}";

  getAuthKeysSource = {pkgs, ...}: {
    source = let
      script = pkgs.writeShellScriptBin getAuthKeysFileName ''
        [[ "$1" != "ghaf" ]] && exit 0
        ${pkgs.coreutils}/bin/cat ${waypipeSshPublicKeyDir}/id_ed25519.pub
      '';
    in "${script}/bin/${getAuthKeysFileName}";
    mode = "0555";
  };

  sshAuthorizedKeysCommand = {
    authorizedKeysCommand = "/etc/${getAuthKeysFilePathInEtc}";
    authorizedKeysCommandUser = "nobody";
  };

  hwDefinition = {
    name = "Lenovo X1 Carbon";
    network.pciDevices = [
      # Passthrough Intel WiFi card 8086:51f1
      {
        path = "0000:00:14.3";
        vendorId = "8086";
        productId = "51f1";
        name = "wlp0s5f0";
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
        fileSystems.${waypipeSshPublicKeyDir}.options = ["ro"];

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
        environment.etc.${getAuthKeysFilePathInEtc} = getAuthKeysSource {inherit pkgs;};
        # Add simple wi-fi connection helper
        environment.systemPackages = lib.mkIf hostConfiguration.config.ghaf.profiles.debug.enable [pkgs.wifi-connector-nmcli];

        services.openssh = sshAuthorizedKeysCommand;

        time.timeZone = "Asia/Dubai";
      })
    ];
    winConfig = hostConfiguration.config.ghaf.windows-launcher;
    networkDevice = hostConfiguration.config.ghaf.hardware.definition.network.pciDevices;
    # TCP port used by PDF XDG handler
    xdgPdfPort = 1200;
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
          # Connect sound device to hosts pulseaudio socket
          "-audiodev"
          "pa,id=pa1,server=unix:/run/pulse/native"
        ];
      }
      ({pkgs, ...}: let
        sshKeyPath = "/run/waypipe-ssh/id_ed25519";
        # The openpdf script is executed by the xdg handler from the chromium-vm
        # It reads the file path, copies it from chromium-vm to zathura-vm and opens it there
        openPdf = with pkgs;
          writeScriptBin "openpdf" ''
            #!${runtimeShell} -e
            read -r sourcepath
            filename=$(basename $sourcepath)
            zathurapath="/var/tmp/$filename"
            chromiumip=$(${dnsutils}/bin/dig +short chromium-vm.ghaf | head -1)
            if [[ "$chromiumip" != "$REMOTE_ADDR" ]]; then
              echo "Open PDF request received from $REMOTE_ADDR, but it is only permitted for chromium-vm.ghaf with IP $chromiumip"
              exit 0
            fi
            echo "Copying $sourcepath from $REMOTE_ADDR to $zathurapath in zathura-vm"
            ${openssh}/bin/scp -i ${sshKeyPath} -o StrictHostKeyChecking=no $REMOTE_ADDR:"$sourcepath" zathura-vm.ghaf:"$zathurapath"
            echo "Opening $zathurapath in zathura-vm"
            ${openssh}/bin/ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no zathura-vm.ghaf run-waypipe zathura "$zathurapath"
            echo "Deleting $zathurapath in zathura-vm"
            ${openssh}/bin/ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no zathura-vm.ghaf rm -f "$zathurapath"
          '';
      in {
        ghaf.hardware.definition.network.pciDevices = networkDevice;
        ghaf.graphics.launchers = let
          adwaitaIconsRoot = "${pkgs.gnome.adwaita-icon-theme}/share/icons/Adwaita/32x32/actions/";
          hostAddress = "192.168.101.2";
          powerControl = pkgs.callPackage powerControlPkgPath {};
        in [
          {
            name = "chromium";
            path = "${pkgs.openssh}/bin/ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no chromium-vm.ghaf run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
            icon = "${../assets/icons/png/browser.png}";
          }

          {
            name = "gala";
            path = "${pkgs.openssh}/bin/ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no gala-vm.ghaf run-waypipe gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
            icon = "${../assets/icons/png/app.png}";
          }

          {
            name = "zathura";
            path = "${pkgs.openssh}/bin/ssh -i ${sshKeyPath} -o StrictHostKeyChecking=no zathura-vm.ghaf run-waypipe zathura";
            icon = "${../assets/icons/png/pdf.png}";
          }

          {
            name = "windows";
            path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
            icon = "${../assets/icons/png/windows.png}";
          }

          {
            name = "nm-launcher";
            path = "${pkgs.nm-launcher}/bin/nm-launcher";
            icon = "${pkgs.networkmanagerapplet}/share/icons/hicolor/22x22/apps/nm-device-wwan.png";
          }

          {
            name = "poweroff";
            path = "${powerControl.makePowerOffCommand {inherit hostAddress sshKeyPath;}}";
            icon = "${adwaitaIconsRoot}/system-shutdown-symbolic.symbolic.png";
          }

          {
            name = "reboot";
            path = "${powerControl.makeRebootCommand {inherit hostAddress sshKeyPath;}}";
            icon = "${adwaitaIconsRoot}/system-reboot-symbolic.symbolic.png";
          }

          # Temporarly disabled as it doesn't work stable
          # {
          #   path = powerControl.makeSuspendCommand {inherit hostAddress sshKeyPath;};
          #   icon = "${adwaitaIconsRoot}/media-playback-pause-symbolic.symbolic.png";
          # }

          # Temporarly disabled as it doesn't work at all
          # {
          #   path = powerControl.makeHibernateCommand {inherit hostAddress sshKeyPath;};
          #   icon = "${adwaitaIconsRoot}/media-record-symbolic.symbolic.png";
          # }
        ];

        time.timeZone = "Asia/Dubai";

        # PDF XDG handler service receives a PDF file path from the chromium-vm and executes the openpdf script
        systemd.user = {
          sockets."pdf" = {
            unitConfig = {
              Description = "PDF socket";
            };
            socketConfig = {
              ListenStream = "${toString xdgPdfPort}";
              Accept = "yes";
            };
            wantedBy = ["sockets.target"];
          };

          services."pdf@" = {
            description = "PDF opener";
            serviceConfig = {
              ExecStart = "${openPdf}/bin/openpdf";
              StandardInput = "socket";
              StandardOutput = "journal";
              StandardError = "journal";
            };
          };
        };

        # Open TCP port for the PDF XDG socket
        networking.firewall.allowedTCPPorts = [xdgPdfPort];
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
          ({
            pkgs,
            config,
            ...
          }: let
            powerControl = pkgs.callPackage powerControlPkgPath {};
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

            environment.etc.${getAuthKeysFilePathInEtc} = getAuthKeysSource {inherit pkgs;};
            services.openssh = sshAuthorizedKeysCommand;

            ghaf = {
              hardware.definition = hwDefinition;
              host.kernel_hardening.enable = false;

              host.hypervisor_hardening.enable = false;

              hardware.x86_64.common.enable = true;

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
        ++ (import ../modules/module-list.nix)
        ++ extraModules;
    };
    package = let inherit ((hostConfiguration.extendModules {modules = [formatModule];})) config; in config.system.build.${config.formatAttr};
  in {
    inherit hostConfiguration package;
    name = "${name}-${variant}";
    installer = let
      pkgs = import nixpkgs {inherit system;};
      inherit ((hostConfiguration.extendModules {modules = [disko.nixosModules.disko (import ../templates/targets/x86_64/generic/disk-config.nix)];}).config.system.build) toplevel;
      installerScript = import ../modules/installer/standalone-installer {
        inherit pkgs;
        toplevelDrv = toplevel;
        inherit (disko.packages.${system}) disko;
        diskoConfig = pkgs.writeText "disko-config.nix" (builtins.readFile ../templates/targets/x86_64/generic/disk-config.nix);
      };
    in
      lib.ghaf.installer {
        inherit system;
        modules = [
          ({pkgs, ...}: {
            # Stop nixos complains about "warning: mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash."
            # NOTE: Why this not working though? https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix#L112
            boot.swraid.mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";

            environment.systemPackages = with pkgs; [
              installerScript
              # Installing this toplevel derivation should include all required
              # packages to installer image /nix/store thus enabling offline
              # installation.
              # hostConfiguration.config.system.build.toplevel

              # Copied from https://github.com/nix-community/disko/blob/f67ba6552845ea5d7f596a24d57c33a8a9dc8de9/lib/default.nix#L396-L402
              # To make disko cli happy without internet.
              util-linux
              e2fsprogs
              mdadm
              zfs
              lvm2
              bash
              jq
            ];
            environment.loginShellInit = ''
              if [[ "$(tty)" == "/dev/tty1" ]] then
                sudo installer.sh
              fi
            '';
            isoImage.storeContents = [toplevel];
          })
        ];
      };
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
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets)
      // builtins.listToAttrs (map (t: lib.nameValuePair "${t.name}-installer" t.installer) targets);
  };
}
