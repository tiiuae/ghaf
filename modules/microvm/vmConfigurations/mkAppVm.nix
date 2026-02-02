# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# App VM Builder - Creates a standalone, extensible app VM configuration
#
# This function creates a base app VM configuration using lib.nixosSystem.
# The result can be extended via .extendModules for composition.
#
# App VMs are dynamically generated based on the vm specification.
# Each app VM can contain multiple applications and custom settings.
#
# Note: `inputs` is passed via specialArgs to lib.nixosSystem, so all modules
# (including base.nix) receive it directly - no currying needed.
#
{ inputs, lib }:
{
  # Target system architecture
  system,
  # VM specification (name, ramMb, cores, applications, etc.)
  vm,
  # GIVC application definitions
  givcApplications ? [ ],
  # Packages from applications
  appPackages ? [ ],
  # Yubi packages
  yubiPackages ? [ ],
  # Extra modules from applications
  appExtraModules ? [ ],
  # Yubi extra modules
  yubiExtra ? [ ],
  # Shared configuration module (debug/release settings, timezone, etc.)
  systemConfigModule ? { },
  # Additional modules to include
  extraModules ? [ ],
}:
let
  vmName = "${vm.name}-vm";

  # App VM specific configuration module (Layer 2: VM role)
  appVmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      networking.hostName = lib.mkDefault vmName;

      ghaf = {
        # User configuration
        users.appUser = {
          enable = true;
          extraGroups = [
            "audio"
            "video"
            "users"
            "plugdev"
          ];
        };

        # System VM type
        type = "app-vm";
        systemd = {
          enable = true;
          withName = "appvm-systemd";
          withLocaled = true;
          withNss = true;
          withResolved = true;
          withTimesyncd = true;
          withPolkit = true;
          withDebug = config.ghaf.profiles.debug.enable or false;
          withHardenedConfigs = true;
        };

        # Storage - base config
        storagevm = {
          enable = true;
          name = vmName;
          directories =
            lib.optionals (!lib.hasAttr "${config.ghaf.users.appUser.name}" config.ghaf.storagevm.users)
              [
                # By default, persist appusers entire home directory unless overwritten
                {
                  directory = "/home/${config.ghaf.users.appUser.name}";
                  user = "${config.ghaf.users.appUser.name}";
                  group = "${config.ghaf.users.appUser.name}";
                  mode = "0700";
                }
              ];
        };

        # Networking
        virtualization.microvm.vm-networking = {
          enable = true;
          inherit vmName;
        };

        # vTPM configuration
        virtualization.microvm.tpm.emulated = {
          inherit (vm.vtpm) enable runInVM;
          inherit (vm) name;
        };

        # Waypipe - base config (serverSocketPath added via extendModules)
        waypipe = {
          inherit (vm.waypipe) enable;
          inherit vm;
        };

        # Audio
        services.audio = lib.mkIf (vm.ghafAudio.enable or false) {
          enable = true;
          role = "client";
        };
      };

      environment.systemPackages = [
        pkgs.opensc
        pkgs.givc-cli
      ]
      ++ (vm.packages or [ ])
      ++ appPackages
      ++ yubiPackages;

      microvm = {
        mem = vm.ramMb * ((vm.balloonRatio or 2) + 1);
        balloon = (vm.balloonRatio or 2) > 0;
        deflateOnOOM = false;
        vcpu = vm.cores;

        shares = [
          {
            tag = "ghaf-common";
            source = "/persist/common";
            mountPoint = "/etc/common";
            proto = "virtiofs";
          }
        ];

        qemu = {
          extraArgs = [
            "-device"
            "qemu-xhci"
          ];
        };
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
    # GIVC configuration
    {
      ghaf.givc.appvm = {
        enable = true;
        applications = givcApplications;
      };
    }
    # Layer 3: Shared system configuration (debug/release, timezone, etc.)
    systemConfigModule
    # Layer 2: App-specific configuration (VM role)
    appVmModule
  ]
  ++ extraModules
  ++ (vm.extraModules or [ ])
  ++ yubiExtra
  ++ appExtraModules;
}
