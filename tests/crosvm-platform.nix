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
  shutdownFor =
    nixos:
    (import ../modules/microvm/common/crosvm-command.nix {
      inherit (nixos) pkgs;
      microvmConfig = nixos.config.microvm;
      macvtapFds = { };
      linuxTarget = nixos.pkgs.linux.target or nixos.pkgs.stdenv.hostPlatform.linux-kernel.target;
    }).shutdownCommand;
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
  protected = makeConfig "aarch64-linux" [
    { microvm.crosvm.protection.mode = "protected-without-firmware"; }
  ];
  protectedWithFirmware = makeConfig "aarch64-linux" [
    {
      microvm.crosvm.protection = {
        mode = "protected-with-firmware";
        firmware = pkgs.writeText "test-pvmfw" "";
      };
    }
  ];
  protectedWithLargerSwiotlb = makeConfig "aarch64-linux" [
    {
      microvm.crosvm.protection = {
        mode = "protected-without-firmware";
        swiotlbSizeMiB = 128;
      };
    }
  ];
  protectedServicePlane = makeConfig "aarch64-linux" [
    {
      microvm = {
        crosvm.protection.mode = "protected-without-firmware";
        interfaces = [
          {
            type = "tap";
            id = "tap-admin-vm";
            mac = "02:ad:00:00:00:03";
          }
        ];
      };
    }
  ];
  protectedMissingFirmware = makeConfig "aarch64-linux" [
    { microvm.crosvm.protection.mode = "protected-with-firmware"; }
  ];
  protectedOnX86 = makeConfig "x86_64-linux" [
    { microvm.crosvm.protection.mode = "protected-without-firmware"; }
  ];
  protectedOnQemu = makeConfig "aarch64-linux" [
    {
      microvm = {
        hypervisor = lib.mkForce "qemu";
        crosvm.protection.mode = "protected-without-firmware";
      };
    }
  ];
  firmwareInUnprotectedMode = makeConfig "aarch64-linux" [
    { microvm.crosvm.protection.firmware = pkgs.writeText "unused-pvmfw" ""; }
  ];
  swiotlbInUnprotectedMode = makeConfig "aarch64-linux" [
    { microvm.crosvm.protection.swiotlbSizeMiB = 128; }
  ];
  protectedWithBalloon = makeConfig "aarch64-linux" [
    {
      microvm = {
        balloon = true;
        crosvm.protection.mode = "protected-without-firmware";
      };
    }
  ];
  protectedWithDevice = makeConfig "aarch64-linux" [
    {
      microvm = {
        crosvm.protection.mode = "protected-without-firmware";
        devices = [
          {
            bus = "pci";
            path = "0000:01:00.0";
          }
        ];
      };
    }
  ];
  protectedWithAssignedDevice = makeConfig "aarch64-linux" [
    {
      microvm = {
        crosvm = {
          deviceTreeOverlays = [ "mgbe0.dtbo" ];
          protection = {
            mode = "protected-without-firmware";
            allowDeviceAssignment = true;
          };
        };
        devices = [
          {
            bus = "platform";
            path = "6800000.ethernet";
            crosvm = {
              dtSymbol = "mgbe0";
              iommu = "pkvm-iommu";
            };
          }
        ];
      };
    }
  ];
  protectedWithShare = makeConfig "aarch64-linux" [
    {
      microvm = {
        crosvm.protection.mode = "protected-without-firmware";
        shares = [
          {
            tag = "test-share";
            source = "/tmp";
            mountPoint = "/tmp/shared";
            proto = "virtiofs";
          }
        ];
      };
    }
  ];
  protectedWithGraphics = makeConfig "aarch64-linux" [
    {
      microvm = {
        crosvm.protection.mode = "protected-without-firmware";
        graphics.enable = true;
      };
    }
  ];
  rawProtectionArg = makeConfig "aarch64-linux" [
    { microvm.crosvm.extraArgs = [ "--protected-vm-without-firmware" ]; }
  ];
  rawSwiotlbArg = makeConfig "aarch64-linux" [
    { microvm.crosvm.extraArgs = [ "--swiotlb" ]; }
  ];
  command = commandFor valid;
  layoutCommand = commandFor layout;
  protectedCommand = commandFor protected;
  protectedFirmwareCommand = commandFor protectedWithFirmware;
  protectedLargerSwiotlbCommand = commandFor protectedWithLargerSwiotlb;
  protectedServicePlaneCommand = commandFor protectedServicePlane;
  aarch64CrossPkgs = import self.inputs.nixpkgs {
    localSystem.system = "x86_64-linux";
    crossSystem.system = "aarch64-linux";
    overlays = [ self.overlays.ghaf-device-manager ];
  };
in
assert lib.hasInfix "--device-tree-overlay 'overlay file.dtbo'" command;
assert lib.hasInfix
  "'/sys/bus/platform/devices/6800000.ethernet test,iommu=off,dt-symbol=mgbe0,mmio-base=0x66000000,map-early=true'"
  command;
assert lib.hasInfix "/sys/bus/pci/devices/0000:01:00.0,iommu=viommu,guest-address=00:1f.0" command;
assert lib.hasInfix "--mem 'size=512,base=0x2000000000'" layoutCommand;
assert lib.hasInfix "--platform-mmio 'base=0x60000000,size=0x1fa0000000'" layoutCommand;
assert lib.hasInfix "--protected-vm-without-firmware" protectedCommand;
assert lib.hasInfix "--protected-vm-with-firmware" protectedFirmwareCommand;
assert lib.hasInfix "--swiotlb 64" protectedCommand;
assert lib.hasInfix "--swiotlb 128" protectedLargerSwiotlbCommand;
assert lib.hasInfix "--net 'tap-name=tap-admin-vm,mac=02:ad:00:00:00:03'"
  protectedServicePlaneCommand;
assert lib.hasInfix "--vsock 77" protectedServicePlaneCommand;
assert !lib.hasInfix "--swiotlb" command;
assert lib.hasInfix "crosvm stop" (shutdownFor protected);
assert lib.hasInfix "crosvm powerbtn" (shutdownFor valid);
assert assertionsPass valid;
assert assertionsPass layout;
assert assertionsPass protected;
assert assertionsPass protectedWithFirmware;
assert assertionsPass protectedWithLargerSwiotlb;
assert assertionsPass protectedServicePlane;
assert assertionsPass protectedWithAssignedDevice;
assert !assertionsPass missingSymbol;
assert !assertionsPass missingOverlay;
assert !assertionsPass unsupportedHypervisor;
assert !assertionsPass fixedPci;
assert !assertionsPass unsupportedLayout;
assert !assertionsPass incompleteLayout;
assert !assertionsPass overlappingLayout;
assert !assertionsPass protectedMissingFirmware;
assert !assertionsPass protectedOnX86;
assert !assertionsPass protectedOnQemu;
assert !assertionsPass firmwareInUnprotectedMode;
assert !assertionsPass swiotlbInUnprotectedMode;
assert !assertionsPass protectedWithBalloon;
assert !assertionsPass protectedWithDevice;
assert !assertionsPass protectedWithShare;
assert !assertionsPass protectedWithGraphics;
assert !assertionsPass rawProtectionArg;
assert !assertionsPass rawSwiotlbArg;
pkgs.runCommand "crosvm-platform"
  {
    nativeBuildInputs = [ pkgs.file ];
  }
  ''
    file ${aarch64CrossPkgs.ghaf-device-manager}/bin/ghaf-device-manager \
      | grep -q 'ARM aarch64'
    touch "$out"
  ''
