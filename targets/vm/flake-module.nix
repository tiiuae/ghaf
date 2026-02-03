# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (inputs) nixos-generators;
  system = "x86_64-linux";
  vm =
    format: variant: withGraphics:
    let
      hostConfiguration = lib.nixosSystem {
        specialArgs = {
          inherit (self) lib;
          inherit inputs; # Required for microvm modules
        };
        modules = [
          (builtins.getAttr format nixos-generators.nixosModules)
          self.nixosModules.common
          self.nixosModules.microvm
          self.nixosModules.profiles
          self.nixosModules.reference-appvms
          self.nixosModules.hardware-x86_64-generic

          (
            { config, pkgs, ... }:
            {
              ghaf = {
                hardware.x86_64.common.enable = true;
                hardware.tpm2.enable = true;
                microvm-boot.enable = lib.mkForce false;

                virtualization = {
                  microvm-host = {
                    enable = true;
                    networkSupport = true;
                  };

                  # TODO: Systemvms enabled but there is no passthroughs
                  microvm.netvm.enable = true;
                  microvm.audiovm.enable = true;
                  microvm.adminvm.enable = true;

                  # TODO: Currently we run the desktop on the host in this target.
                  # GUI VM usage would require some display forwarding or remote display connection
                  # microvm.guivm.enable = withGraphics;

                  microvm.appvm = {
                    enable = true;
                    vms = {
                      zathura = {
                        enable = true;
                        waypipe.enable = false; # disable waypipe when guivm is not used
                      };
                      gala = {
                        enable = false;
                        waypipe.enable = withGraphics;
                      };
                    };
                  };
                };

                reference = {
                  appvms.enable = true;
                };

                # Add some launchers
                # TODO: The application interface needs to move to a common module to be reused here
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
                  port = lib.mkForce "9002";
                };
                services = [ ];
                eventProxy = lib.mkForce [ ];
              };

              # Reorder some GIVC services to ensure proper startup order in host
              systemd.services = lib.optionalAttrs withGraphics {
                givc-key-setup.after = [ "local-fs.target" ];
                givc-user-key-setup.after = [ "givc-key-setup.service" ];
              };

              # Reconfigure net-vm and audio-vm socket proxies to connect with host
              microvm.vms = lib.optionalAttrs withGraphics {
                net-vm.config.config.givc.sysvm = {
                  hwidService = lib.mkForce false;
                  socketProxy = lib.mkForce [
                    {
                      transport = {
                        name = config.networking.hostName;
                        addr = config.ghaf.networking.hosts.${config.networking.hostName}.ipv4;
                        port = "9010";
                        protocol = "tcp";
                      };
                      socket = "/tmp/dbusproxy_net.sock";
                    }
                  ];
                };
                audio-vm.config.config.givc.sysvm.socketProxy = lib.mkForce [
                  {
                    transport = {
                      name = config.networking.hostName;
                      addr = config.ghaf.networking.hosts.${config.networking.hostName}.ipv4;
                      port = "9011";
                      protocol = "tcp";
                    };
                    socket = "/tmp/dbusproxy_snd.sock";
                  }
                ];
              };

              nixpkgs = {
                hostPlatform.system = system;

                # Increase the support for different devices by allowing the use
                # of proprietary drivers from the respective vendors
                config = {
                  allowUnfree = true;
                  #jitsi was deemed insecure because of an obsecure potential security
                  #vulnerability but it is still used by many people
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
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
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
