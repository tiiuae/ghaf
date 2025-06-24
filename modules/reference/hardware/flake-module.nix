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
        ghaf.hardware.usb.vhotplug.enable = true;
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
        ghaf.hardware.usb.vhotplug.enable = true;
      }
    ];
    hardware-dell-latitude-7330.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./dell-latitude/definitions/dell-latitude-7330.nix;
        ghaf.hardware.usb.vhotplug.enable = true;
      }
    ];
    hardware-demo-tower-mk1.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./demo-tower/demo-tower.nix;
        ghaf.hardware.usb.vhotplug.enable = true;
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
        ghaf.hardware.usb.vhotplug.enable = true;
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
        ghaf.hardware.usb.vhotplug.enable = true;
      }
    ];
    hardware-lenovo-x1-carbon-gen11.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen11.nix;
        ghaf.hardware.passthrough.mode = "dynamic";
        ghaf.hardware.passthrough.secure-hotplug.enable = true;
        ghaf.hardware.passthrough.secure-hotplug.usb.dynamicUpdateRules = true;
        ghaf.hardware.passthrough.secure-hotplug.usb.hotplugRules = {
          allowlist = {
            "0x0b95:0x1790" = [ "net-vm" ]; # ASIX Elec. Corp. AX88179 UE306 Ethernet Adapter
            "0x04f2:0xb751" = [ "business-vm" ]; # Lenovo integrated camera, Finland SKU
            "0x5986:0x2145" = [ "business-vm" ]; # Lenovo integrated camera, UAE SKU
            "0x30c9:0x0052" = [ "business-vm" ]; # Lenovo integrated camera, UAE SKU
            "0x30c9:0x005f" = [ "business-vm" ]; # Lenovo integrated camera, Finland SKU
          };
          classlist = {
            "0x01:*:*" = [ "audio-vm" ];
            "0x03:*:0x01" = [ "gui-vm" ];
            "0x03:*:0x02" = [ "gui-vm" ];
            "0x08:0x06:*" = [ "gui-vm" ];
            "0x0b:*:*" = [ "gui-vm" ];
            "0x11:*:*" = [ "gui-vm" ];
            "0x02:0x06:*" = [ "net-vm" ];
            "0x0e:*:*" = [ "chrome-vm" ];
          };
        };
      }
    ];
    hardware-lenovo-x1-carbon-gen12.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen12.nix;
        ghaf.hardware.usb.vhotplug.enable = true;
      }
    ];
    hardware-lenovo-x1-carbon-gen13.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen13.nix;
        ghaf.hardware.usb.vhotplug.enable = true;
      }
    ];
    hardware-lenovo-x1-2-in-1-gen9.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-2-in-1-gen-9.nix;
        ghaf.hardware.usb.vhotplug.enable = true;
      }
    ];
    imx8.imports = [ ./imx8 ];
    polarfire.imports = [ ./polarfire ];
    jetpack.imports = [
      ./jetpack
      ./jetpack/nvidia-jetson-orin/optee.nix
      inputs.self.nixosModules.hardware-aarch64-generic
    ];
    hardware-nvidia-jetson-orin-agx.imports = [
      inputs.self.nixosModules.jetpack
      ./jetpack/agx/orin-agx.nix
    ];
    hardware-nvidia-jetson-orin-agx64.imports = [
      inputs.self.nixosModules.jetpack
      ./jetpack/agx/orin-agx64.nix
    ];
    hardware-nvidia-jetson-orin-nx.imports = [
      inputs.self.nixosModules.jetpack
      ./jetpack/nx/orin-nx.nix
    ];
  };
}
