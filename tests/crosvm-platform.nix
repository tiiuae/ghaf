# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, self }:
let
  inherit (pkgs) lib;
  makeConfig =
    system: modules:
    self.inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.microvm-guest
        {
          networking.hostName = "crosvm-platform-test";
          system.stateVersion = "25.11";
          microvm = {
            hypervisor = "crosvm";
            vsock.cid = 77;
          };
        }
      ]
      ++ modules;
    };
  commandFor =
    nixos:
    (import ../modules/microvm/common/crosvm-command.nix {
      inherit (nixos) pkgs;
      microvmConfig = nixos.config.microvm;
      macvtapFds = { };
      linuxTarget = nixos.pkgs.linux.target or nixos.pkgs.stdenv.hostPlatform.linux-kernel.target;
    }).command;
  assertionsPass = nixos: builtins.all ({ assertion, ... }: assertion) nixos.config.assertions;
  valid = makeConfig "x86_64-linux" [
    {
      microvm = {
        crosvm.deviceTreeOverlays = [ "overlay file.dtbo" ];
        devices = [
          {
            bus = "platform";
            path = "6800000.ethernet test";
            crosvm.dtSymbol = "mgbe0";
            crosvm.mmioBase = lib.fromHexString "0x66000000";
            crosvm.mapEarly = true;
          }
          {
            bus = "pci";
            path = "0000:01:00.0";
            crosvm.guestAddress = "00:1f.0";
          }
        ];
      };
    }
  ];
  layout = makeConfig "aarch64-linux" [
    {
      microvm.crosvm = {
        memoryBase = lib.fromHexString "0x2000000000";
        platformMmio = {
          base = lib.fromHexString "0x60000000";
          size = lib.fromHexString "0x1fa0000000";
        };
      };
    }
  ];
  missingSymbol = makeConfig "x86_64-linux" [
    {
      microvm = {
        crosvm.deviceTreeOverlays = [ "overlay.dtbo" ];
        devices = [
          {
            bus = "platform";
            path = "6800000.ethernet";
          }
        ];
      };
    }
  ];
  missingOverlay = makeConfig "x86_64-linux" [
    {
      microvm.devices = [
        {
          bus = "platform";
          path = "6800000.ethernet";
          crosvm.dtSymbol = "mgbe0";
        }
      ];
    }
  ];
  unsupportedHypervisor = makeConfig "x86_64-linux" [
    {
      microvm = {
        hypervisor = lib.mkForce "qemu";
        crosvm.deviceTreeOverlays = [ "overlay.dtbo" ];
        devices = [
          {
            bus = "platform";
            path = "6800000.ethernet";
            crosvm.dtSymbol = "mgbe0";
          }
        ];
      };
    }
  ];
  fixedPci = makeConfig "x86_64-linux" [
    {
      microvm.devices = [
        {
          bus = "pci";
          path = "0000:01:00.0";
          crosvm.mmioBase = lib.fromHexString "0x66000000";
        }
      ];
    }
  ];
  unsupportedLayout = makeConfig "x86_64-linux" [
    {
      microvm.crosvm = {
        memoryBase = lib.fromHexString "0x2000000000";
        platformMmio = {
          base = lib.fromHexString "0x60000000";
          size = lib.fromHexString "0x1fa0000000";
        };
      };
    }
  ];
  incompleteLayout = makeConfig "aarch64-linux" [
    { microvm.crosvm.memoryBase = lib.fromHexString "0x2000000000"; }
  ];
  overlappingLayout = makeConfig "aarch64-linux" [
    {
      microvm.crosvm = {
        memoryBase = lib.fromHexString "0x80000000";
        platformMmio = {
          base = lib.fromHexString "0x90000000";
          size = lib.fromHexString "0x10000000";
        };
      };
    }
  ];
  command = commandFor valid;
  layoutCommand = commandFor layout;
in
assert lib.hasInfix "--device-tree-overlay 'overlay file.dtbo'" command;
assert lib.hasInfix
  "'/sys/bus/platform/devices/6800000.ethernet test,iommu=off,dt-symbol=mgbe0,mmio-base=0x66000000,map-early=true'"
  command;
assert lib.hasInfix "/sys/bus/pci/devices/0000:01:00.0,iommu=viommu,guest-address=00:1f.0" command;
assert lib.hasInfix "--mem 'size=512,base=0x2000000000'" layoutCommand;
assert lib.hasInfix "--platform-mmio 'base=0x60000000,size=0x1fa0000000'" layoutCommand;
assert assertionsPass valid;
assert assertionsPass layout;
assert !assertionsPass missingSymbol;
assert !assertionsPass missingOverlay;
assert !assertionsPass unsupportedHypervisor;
assert !assertionsPass fixedPci;
assert !assertionsPass unsupportedLayout;
assert !assertionsPass incompleteLayout;
assert !assertionsPass overlappingLayout;
pkgs.runCommand "crosvm-platform" { } "touch $out"
