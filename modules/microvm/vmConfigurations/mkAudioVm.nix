# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Builder - Creates a standalone, extensible audio VM configuration
#
# This function creates a base audio VM configuration using lib.nixosSystem.
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
  vmName = "audio-vm";

  # Audio VM specific configuration module (Layer 2: VM role)
  audioVmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      networking.hostName = lib.mkDefault vmName;

      ghaf = {
        users.proxyUser = {
          enable = true;
          extraGroups = [
            "audio"
            "pipewire"
            "bluetooth"
          ];
        };

        # System VM type
        type = "system-vm";
        systemd = {
          enable = true;
          withName = "audiovm-systemd";
          withLocaled = true;
          withAudio = true;
          withBluetooth = true;
          withNss = true;
          withResolved = true;
          withTimesyncd = true;
          withDebug = config.ghaf.profiles.debug.enable;
          withHardenedConfigs = true;
        };
        givc.audiovm.enable = true;

        # Storage - base config, encryption enabled via extendModules
        storagevm = {
          enable = true;
          name = vmName;
        };

        # Networking
        virtualization.microvm.vm-networking = {
          enable = true;
          inherit vmName;
        };

        # Services
        services = {
          audio = {
            enable = true;
            role = "server";
            server.pipewireForwarding.enable = true;
          };
          power-manager.vm = {
            enable = true;
            pciSuspendServices = [
              "pipewire.socket"
              "pipewire.service"
              "bluetooth.service"
            ];
          };
          performance.vm.enable = true;
        };

        # Logging - enabled based on profile
        logging.client.enable = config.ghaf.logging.enable or false;

        # Security
        security.fail2ban.enable = config.ghaf.development.ssh.daemon.enable or false;
      };

      environment.systemPackages = [
        pkgs.pulseaudio
        pkgs.pamixer
        pkgs.pipewire
      ]
      ++ lib.optional (config.ghaf.development.debug.tools.enable or false) pkgs.alsa-utils;

      microvm = {
        vcpu = 2;
        mem = 384;

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
    # Layer 3: Shared system configuration (debug/release, timezone, etc.)
    systemConfigModule
    # Layer 2: Audio-specific configuration (VM role)
    audioVmModule
  ]
  ++ extraModules;
}
