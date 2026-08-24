# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, self }:
let
  inherit (pkgs) lib;
  makeConfig =
    system: module:
    self.inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        self.nixosModules.microvm-nix
        {
          networking.hostName = "crosvm-platform-test";
          system.stateVersion = "25.11";
          microvm = {
            hypervisor = "crosvm";
            vsock.cid = 77;
          };
        }
        module
      ];
    };
  assertionsPass = nixos: builtins.all ({ assertion, ... }: assertion) nixos.config.assertions;
  upstream = makeConfig "x86_64-linux" { };
  pci = makeConfig "x86_64-linux" {
    microvm = {
      devices = [
        {
          bus = "pci";
          path = "0000:01:00.0";
        }
      ];
      crosvm.pciDeviceOptions."0000:01:00.0" = {
        guestAddress = "00:1f.0";
        iommu = "off";
      };
    };
  };
  layout = makeConfig "aarch64-linux" {
    microvm.crosvm.memoryBase = lib.fromHexString "0x2000000000";
  };
  missingPci = makeConfig "x86_64-linux" {
    microvm.crosvm.pciDeviceOptions."0000:01:00.0".iommu = "off";
  };
  unsupportedLayout = makeConfig "x86_64-linux" {
    microvm.crosvm.memoryBase = lib.fromHexString "0x2000000000";
  };
  aarch64CrossPkgs = import self.inputs.nixpkgs {
    localSystem.system = "x86_64-linux";
    crossSystem.system = "aarch64-linux";
    overlays = [ self.overlays.ghaf-device-manager ];
  };
in
assert assertionsPass pci;
assert assertionsPass layout;
assert !assertionsPass missingPci;
assert !assertionsPass unsupportedLayout;
pkgs.runCommand "crosvm-platform"
  {
    nativeBuildInputs = [ pkgs.file ];
  }
  ''
    grep -Fq -- 'iommu=off,guest-address=00:1f.0' \
      ${pci.config.microvm.runner.crosvm}/bin/microvm-run
    grep -Fq -- 'size=512,base=0x2000000000' \
      ${layout.config.microvm.runner.crosvm}/bin/microvm-run
    test "$(readlink ${pci.config.microvm.runner.crosvm}/bin/microvm-shutdown)" = \
      "$(readlink ${upstream.config.microvm.runner.crosvm}/bin/microvm-shutdown)"
    file ${aarch64CrossPkgs.ghaf-device-manager}/bin/ghaf-device-manager | grep -q 'ARM aarch64'
    touch "$out"
  ''
