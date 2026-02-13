# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Target - QEMU VM for development and testing
#
# This target runs GUI on the HOST (not in a gui-vm microvm).
# VMs: netvm, audiovm, adminvm, appvms (zathura)
#
{
  inputs,
  lib,
  self,
  ...
}:
let
  system = "x86_64-linux";
  buildAttrs = {
    vm = "vm";
    vmware = "vmwareImage";
  };
  formatModules = {
    vm =
      { modulesPath, lib, ... }:
      {
        imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
        virtualisation.diskSize = lib.mkDefault (2 * 1024);
      };
    vmware =
      { modulesPath, ... }:
      {
        imports = [ "${modulesPath}/virtualisation/vmware-image.nix" ];
      };
  };
  vm =
    format: variant: withGraphics:
    let
      hostConfiguration = lib.nixosSystem {
        specialArgs = {
          inherit (self) lib;
          inherit inputs;
        };
        modules = [
          formatModules.${format}
          self.nixosModules.profiles-vm
          self.nixosModules.hardware-x86_64-generic

          (
            { config, pkgs, ... }:
            let
              # Helper for GIVC transport config pointing to host
              inherit (config.networking) hostName;
              hostIpv4 = config.ghaf.networking.hosts.${hostName}.ipv4;

              # GIVC config for netvm - point socket proxy to host
              netvmGivcModule = lib.optionalAttrs withGraphics {
                givc.sysvm = {
                  hwidService = lib.mkForce false;
                  socketProxy = lib.mkForce [
                    {
                      transport = {
                        name = hostName;
                        addr = hostIpv4;
                        port = "9010"; # GIVC netvm proxy port
                        protocol = "tcp";
                      };
                      socket = "/tmp/dbusproxy_net.sock"; # D-Bus proxy for NetworkManager
                    }
                  ];
                };
              };

              # GIVC config for audiovm - point socket proxy to host
              audiovmGivcModule = lib.optionalAttrs withGraphics {
                givc.sysvm.socketProxy = lib.mkForce [
                  {
                    transport = {
                      name = hostName;
                      addr = hostIpv4;
                      port = "9011"; # GIVC audiovm proxy port
                      protocol = "tcp";
                    };
                    socket = "/tmp/dbusproxy_snd.sock"; # D-Bus proxy for PulseAudio/Blueman
                  }
                ];
              };

              # Reference to profile for convenience
              vmProfile = config.ghaf.profiles.vm;
            in
            {
              ghaf = {
                # Enable the VM profile (creates netvmBase, audiovmBase, adminvmBase, mkAppVm)
                profiles.vm.enable = true;

                hardware.x86_64.common.enable = true;
                hardware.tpm2.enable = true;

                microvm-boot.enable = lib.mkForce false;

                virtualization = {
                  microvm-host = {
                    enable = true;
                    networkSupport = true;
                  };

                  # Wire up VM evaluatedConfigs using the profile's bases
                  microvm = {
                    netvm = {
                      enable = true;
                      evaluatedConfig = vmProfile.netvmBase.extendModules {
                        modules = [ netvmGivcModule ];
                      };
                    };

                    audiovm = {
                      enable = true;
                      evaluatedConfig = vmProfile.audiovmBase.extendModules {
                        modules = [ audiovmGivcModule ];
                      };
                    };

                    adminvm = {
                      enable = true;
                      evaluatedConfig = vmProfile.adminvmBase;
                    };

                    # NOTE: GUI runs on host, not in a gui-vm
                    # guivm.enable = withGraphics;

                    # AppVMs - configured inline since reference-appvms uses laptop-x86 profile
                    appvm = {
                      enable = true;
                      vms = {
                        zathura = {
                          enable = true;
                          # Create evaluatedConfig with waypipe disabled (no guivm)
                          evaluatedConfig = vmProfile.mkAppVm {
                            name = "zathura";
                            ramMb = 512;
                            cores = 1;
                            borderColor = "#122263"; # Dark blue — security context indicator
                            waypipe.enable = false; # No guivm, so no waypipe
                            applications = [
                              {
                                name = "PDF Viewer";
                                description = "Isolated PDF Viewer";
                                packages = [ pkgs.zathura ];
                                icon = "document-viewer";
                                command = "zathura";
                              }
                            ];
                          };
                        };
                      };
                    };
                  };
                };

                # Add some launchers for host GUI
                graphics.launchers = lib.optionals withGraphics [
                  {
                    name = "Calculator";
                    description = "Solve Math Problems";
                    icon = "${pkgs.gnome-calculator}/share/icons/hicolor/scalable/apps/org.gnome.Calculator.svg";
                    execPath = "${pkgs.gnome-calculator}/bin/gnome-calculator";
                  }
                  {
                    name = "Bluetooth Settings";
                    description = "Manage Bluetooth Devices & Settings";
                    icon = "bluetooth-48";
                    execPath = "${pkgs.writeShellScriptBin "bluetooth-settings" ''
                      DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock \
                      PULSE_SERVER=audio-vm:${toString config.ghaf.services.audio.server.pulseaudioTcpControlPort} \
                      ${pkgs.blueman}/bin/blueman-manager
                    ''}/bin/bluetooth-settings";
                  }
                ];

                # Add simple login user for testing purposes
                users.managed = [
                  {
                    name = "user";
                    vms = [ "ghaf-host" ];
                    initialPassword = "ghaf";
                    uid = 1000;
                    extraGroups = [
                      "wheel"
                    ];
                  }
                ];

                givc = {
                  enable = withGraphics;
                  debug = true;
                  # We enable the gui-vm module as the desktop runs on the host
                  guivm.enable = withGraphics;
                };

                host = {
                  networking.enable = true;
                };

                # Enable all the default UI applications
                profiles = {
                  graphics = {
                    enable = withGraphics;
                  };
                  release.enable = variant == "release";
                  debug.enable = lib.hasPrefix "debug" variant;
                };
              };

              # Enable GUI component on host
              givc.sysvm = lib.optionalAttrs withGraphics {
                transport = {
                  name = lib.mkForce "ghaf-host-gui";
                  addr = config.ghaf.networking.hosts.ghaf-host.ipv4;
                  port = lib.mkForce "9002"; # GIVC host GUI transport port
                };
                services = [ ];
                eventProxy = lib.mkForce [ ];
              };

              # Reorder some GIVC services to ensure proper startup order in host
              systemd.services = lib.optionalAttrs withGraphics {
                givc-key-setup.after = [ "local-fs.target" ];
                givc-user-key-setup.after = [ "givc-key-setup.service" ];
              };

              nixpkgs = {
                hostPlatform.system = system;

                config = {
                  allowUnfree = true;
                  permittedInsecurePackages = [
                    "jitsi-meet-1.0.8043"
                    "qtwebengine-5.15.19"
                  ];
                };

                overlays = [ self.overlays.default ];
              };

              virtualisation = lib.optionalAttrs (format == "vm") {
                graphics = withGraphics;
                useNixStoreImage = true;
                writableStore = true;
                cores = 4;
                memorySize = 8 * 1024;
                forwardPorts = [
                  {
                    from = "host";
                    host.port = 8022;
                    guest.port = 22;
                  }
                ];
                tpm.enable = true;
              };
            }
          )
        ];
      };
    in
    {
      inherit hostConfiguration;
      name = "${format}-${variant}";
      package = hostConfiguration.config.system.build.${buildAttrs.${format}};
    };
  targets = [
    (vm "vm" "debug" true)
    (vm "vm" "debug-nogui" false)
    (vm "vm" "release" true)
    (vm "vmware" "debug" true)
  ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages = {
      x86_64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
