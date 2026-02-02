# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Role Configuration - Layer 2
#
# This module defines the audio VM role, extending the base VM configuration.
# It is designed to receive system settings via the shared systemConfigModule
# and host-specific bindings via extendModules.
#
# Note: This module receives `inputs` via specialArgs from the parent
# lib.nixosSystem call - no currying needed.
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  vmName = "audio-vm";
in
{
  imports = [
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
  ];

  ghaf = {
    # Profiles - these should come from systemConfigModule
    # debug/release settings are inherited from the shared module

    users.proxyUser = {
      enable = true;
      extraGroups = [
        "audio"
        "pipewire"
        "bluetooth"
      ];
    };

    # System
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

    # Enable dynamic hostname export for VMs
    identity.vmHostNameExport.enable = true;

    # Storage - encryption setting comes from systemConfigModule or extendModules
    storagevm = {
      enable = true;
      name = vmName;
      # encryption.enable is set by host bindings
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
      performance.vm = {
        enable = true;
      };
    };

    # Logging - enabled based on profile
    logging.client.enable = config.ghaf.logging.enable or false;

    # Security
    security.fail2ban.enable = config.ghaf.development.ssh.daemon.enable or false;
  };

  environment = {
    systemPackages = [
      pkgs.pulseaudio
      pkgs.pamixer
      pkgs.pipewire
    ]
    ++ lib.optional (config.ghaf.development.debug.tools.enable or false) pkgs.alsa-utils;
  };

  microvm = {
    optimize.enable = false;
    vcpu = 2;
    mem = 384;
    hypervisor = "qemu";

    shares = [
      {
        tag = "ghaf-common";
        source = "/persist/common";
        mountPoint = "/etc/common";
        proto = "virtiofs";
      }
    ];
    # Note: Store shares and storeOnDisk are added by host bindings

    qemu = {
      extraArgs = [
        "-device"
        "qemu-xhci"
      ];
      # machine type is set by host bindings based on platform
    };
  };
}
