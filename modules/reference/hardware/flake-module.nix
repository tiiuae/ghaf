# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ inputs, lib, ... }:
{
  flake.nixosModules = {
    hardware-alienware-m18-r2.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./alienware/alienware-m18.nix;
        ghaf.virtualization.microvm.guivm.extraModules = [
          (import ./alienware/extra-config.nix)
        ];
        ghaf.virtualization.microvm.netvm.extraModules = [
          (import ./alienware/net-config.nix)
        ];
      }
    ];
    hardware-dell-latitude-7230.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./dell-latitude/definitions/dell-latitude-7230.nix;
      }
    ];
    hardware-dell-latitude-7330-72.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./dell-latitude/definitions/dell-latitude-7330-72.nix;
      }
    ];
    # New variant as network device may enumerate on different PCI BUS on same model of Dell 7330
    # TODO: Remove once we can have better way to detect network PCI device
    hardware-dell-latitude-7330-71.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./dell-latitude/definitions/dell-latitude-7330-71.nix;
      }
    ];
    hardware-demo-tower-mk1.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./demo-tower/demo-tower.nix;
        ghaf.hardware.tpm2.enable = lib.mkForce false;
        ghaf.virtualization.microvm.guivm.extraModules = [
          (import ./demo-tower/extra-config.nix)
        ];
      }
    ];
    hardware-tower-5080.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./tower-5080/tower-5080.nix;
        ghaf.hardware.tpm2.enable = lib.mkForce false;
        ghaf.virtualization.microvm.guivm.extraModules = [
          (import ./tower-5080/extra-config.nix)
        ];
      }
    ];
    hardware-lenovo-x1-carbon-gen10.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen10.nix;
      }
    ];
    hardware-lenovo-x1-carbon-gen11.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen11.nix;
      }
    ];
    hardware-lenovo-x1-carbon-gen12.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen12.nix;
      }
    ];
    imx8.imports = [ ./imx8 ];
    #TODO: Technically all the module imports can happen at this level
    # without the need to drive the inputs down another level.
    # could make discoverability easier.
    jetpack.imports = [
      ./jetpack
      inputs.self.nixosModules.hardware-aarch64-generic
    ];
    polarfire.imports = [ ./polarfire ];
  };
}
