# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# IDS VM Base Module
#
# This module contains the full IDS VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.idsvm-base ];
#     specialArgs = { inherit globalConfig hostConfig; };
#   }
#
# Then extend with:
#   base.extendModules { modules = [ ... ]; }
#
{
  lib,
  pkgs,
  inputs,
  globalConfig,
  hostConfig,
  ...
}:
let
  vmName = "ids-vm";
in
{
  _file = ./idsvm-base.nix;

  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.self.nixosModules.profiles
    ./mitmproxy
  ];

  ghaf = {
    type = "system-vm";
    profiles.debug.enable = lib.mkDefault (globalConfig.debug.enable or false);

    # MiTM proxy feature - from globalConfig
    virtualization.microvm.idsvm.mitmproxy.enable = globalConfig.idsvm.mitmproxy.enable or false;

    development = {
      # NOTE: SSH port also becomes accessible on the network interface
      #       that has been passed through to NetVM
      ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
    };

    # Networking - IDS VM acts as gateway
    virtualization.microvm.vm-networking = {
      enable = true;
      isGateway = true;
      inherit vmName;
    };

    # Networking hosts - from hostConfig (for vm-networking.nix to look up MAC/IP)
    networking.hosts = hostConfig.networking.hosts or { };

    # Common namespace - from hostConfig (previously from commonModule in modules.nix)
    common = hostConfig.common or { };
  };

  system.stateVersion = lib.trivial.release;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
  };

  # IDS-specific packages
  environment.systemPackages = [
    pkgs.snort # TODO: put into separate module
  ]
  ++ (lib.optional (globalConfig.debug.enable or false) pkgs.tcpdump);

  microvm = {
    hypervisor = "qemu";
    optimize.enable = true;
    # Sensible defaults - can be overridden via vmConfig
    vcpu = lib.mkDefault 2;
    mem = lib.mkDefault 512;

    # Shared store (when not using storeOnDisk)
    shares = lib.optionals (!(globalConfig.storage.storeOnDisk or false)) [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
    ];

    writableStoreOverlay = lib.mkIf (!(globalConfig.storage.storeOnDisk or false)) "/nix/.rw-store";
  }
  // lib.optionalAttrs (globalConfig.storage.storeOnDisk or false) {
    storeOnDisk = true;
    storeDiskType = "erofs";
    storeDiskErofsFlags = [
      "-zlz4hc"
      "-Eztailpacking"
    ];
  };
}
