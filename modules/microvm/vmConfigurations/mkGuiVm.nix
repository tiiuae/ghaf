# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Builder - Creates a standalone, extensible GUI VM configuration
#
# This function creates a base GUI VM configuration using lib.nixosSystem.
# The result can be extended via .extendModules for composition.
#
# Note: `inputs` is passed via specialArgs to lib.nixosSystem, so all modules
# (including base.nix) receive it directly - no currying needed.
#
{ inputs, lib }:
{
  # Target system architecture
  system,
  # Shared configuration module (debug/release settings, timezone, etc.)
  systemConfigModule ? { },
  # Additional modules to include
  extraModules ? [ ],
}:
let
  vmName = "gui-vm";

  inherit (lib) rmDesktopEntries;

  # GUI VM specific configuration module (Layer 2: VM role)
  guiVmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        # Reference services for orbit etc.
        ../../reference/services
      ];

      networking.hostName = lib.mkDefault vmName;

      ghaf = {
        # Profiles
        profiles.graphics.enable = true;

        users = {
          # AD users and homed user configured via extendModules
        };

        # System
        type = "system-vm";
        systemd = {
          enable = true;
          withName = "guivm-systemd";
          withHomed = true;
          withLocaled = true;
          withNss = true;
          withResolved = true;
          withTimesyncd = true;
          withDebug = config.ghaf.profiles.debug.enable;
          withHardenedConfigs = true;
        };
        givc.guivm.enable = true;

        # Storage - base config, specifics via extendModules
        storagevm = {
          enable = true;
          name = vmName;
          shared-folders = {
            enable = true;
            isGuiVm = true;
          };
        };

        # Networking
        virtualization.microvm.vm-networking = {
          enable = true;
          inherit vmName;
        };

        # Graphics boot
        graphics.boot = {
          enable = true;
          renderer = "gpu";
        };

        # Logging - enabled based on profile
        logging.client.enable = config.ghaf.logging.enable or false;

        # Services
        services = {
          user-provisioning.enable = true;
          audio = {
            enable = true;
            role = "client";
            client.pipewireControl.enable = true;
          };
          power-manager = {
            vm.enable = true;
            gui.enable = true;
          };
          kill-switch.enable = true;
          performance.gui.enable = true;
          github = {
            enable = true;
            token = "xxxxxxxxxxxxxxxxxxxx"; # Updated on user login
            owner = "tiiuae";
            repo = "ghaf-bugreports";
          };
          timezone.enable = true;
          locale.enable = true;
          disks.enable = true;
        };
        xdgitems.enable = true;

        # Security
        security.fail2ban.enable = config.ghaf.development.ssh.daemon.enable or false;
      };

      services = {
        dbus.packages = [ pkgs.blueman ];
        orbit = {
          enable = true;
          enrollSecretPath = "/etc/common/ghaf/fleet/enroll";
          fleetUrl = "https://fleetdm.vedenemo.dev";
          hostnameFile = "/etc/common/ghaf/hostname";
          rootDir = "/etc/common/ghaf/orbit";
          enableScripts = true;
          hostIdentifier = "specified";
          osqueryPackage = lib.mkForce pkgs."osquery-with-hostname";
        };
      };

      systemd = {
        packages = [ pkgs.blueman ];
        user.services."fleet-desktop".enable = false;
        # waypipe-ssh-keygen service configured via extendModules (needs uid info)
      };

      environment.systemPackages =
        (rmDesktopEntries [
          pkgs.waypipe
          pkgs.gnome-calculator
          pkgs.sticky-notes
        ])
        ++ [ pkgs.ctrl-panel ]
        ++ lib.optional (config.ghaf.profiles.debug.enable or false) pkgs.givc-cli
        ++ lib.optionals (config.ghaf.profiles.debug.enable or false) [
          pkgs.mesa-demos
          pkgs.libva-utils
          pkgs.glib
        ]
        ++ [ pkgs.vhotplug ];

      microvm = {
        vcpu = 6;
        mem = 12288;

        shares = [
          {
            tag = "ghaf-common";
            source = "/persist/common";
            mountPoint = "/etc/common";
            proto = "virtiofs";
          }
        ];

        qemu.extraArgs = [
          "-device"
          "qemu-xhci"
        ];
      };
    };
in
lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit lib inputs;
  };
  modules = [
    # Core microvm module
    inputs.microvm.nixosModules.microvm
    # Guest kernel for x86_64
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    # Layer 1: Base VM configuration (common defaults) - gets inputs via specialArgs
    ./base.nix
    # nixpkgs configuration (must match host settings)
    {
      nixpkgs = {
        hostPlatform.system = system;
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
            "jitsi-meet-1.0.8043"
            "qtwebengine-5.15.19"
          ];
        };
        overlays = [ inputs.self.overlays.default ];
      };
    }
    # Layer 3: Shared system configuration (debug/release, timezone, etc.)
    systemConfigModule
    # Layer 2: GUI-specific configuration (VM role)
    guiVmModule
  ]
  ++ extraModules;
}
