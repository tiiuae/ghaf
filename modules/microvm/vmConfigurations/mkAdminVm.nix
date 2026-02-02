# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Builder - Creates a standalone, extensible admin VM configuration
#
# This function creates a base admin VM configuration using lib.nixosSystem.
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
  vmName = "admin-vm";

  # Admin VM specific configuration module (Layer 2: VM role)
  adminVmModule =
    {
      config,
      lib,
      ...
    }:
    {
      networking.hostName = lib.mkDefault vmName;

      ghaf = {
        # System
        type = "admin-vm";
        systemd = {
          enable = true;
          withName = "adminvm-systemd";
          withLocaled = true;
          withNss = true;
          withResolved = true;
          withPolkit = true;
          withTimesyncd = true;
          withDebug = config.ghaf.profiles.debug.enable;
          withHardenedConfigs = true;
        };
        givc.adminvm.enable = true;

        # Storage - base config
        storagevm = {
          enable = true;
          name = vmName;
          files = [
            "/etc/locale-givc.conf"
            "/etc/timezone.conf"
          ];
        };

        # Networking
        virtualization.microvm.vm-networking = {
          enable = true;
          inherit vmName;
        };

        # Logging
        logging.recovery.enable = true;

        # Security
        security.fail2ban.enable = config.ghaf.development.ssh.daemon.enable or false;
      };

      microvm = {
        shares = [
          {
            tag = "ghaf-common";
            source = "/persist/common";
            mountPoint = "/etc/common";
            proto = "virtiofs";
          }
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
    # nixpkgs configuration
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
    # Layer 2: Admin-specific configuration (VM role)
    adminVmModule
  ]
  ++ extraModules;
}
