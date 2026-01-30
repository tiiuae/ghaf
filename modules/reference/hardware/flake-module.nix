# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ inputs, lib, ... }:
{
  # keep-sorted start skip_lines=1 block=yes newline_separated=yes by_regex=\s*nixosModules\.(.*)$ prefix_order=hardware-x86_64-workstation,jetpack
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

    hardware-dell-latitude-7330.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./dell-latitude/definitions/dell-latitude-7330.nix;
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

    hardware-intel-laptop.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./intel-laptop/intel-laptop.nix;
        ghaf.hardware.passthrough.pci.autoDetectGpu = true;
        ghaf.hardware.passthrough.pci.autoDetectNet = true;
        ghaf.hardware.passthrough.pci.autoDetectAudio = true;
      }
    ];

    hardware-lenovo-t14-amd-gen5.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-t14-amd/definitions/gen-5.nix;
        ghaf.virtualization.microvm.guivm.extraModules = [
          ./lenovo-t14-amd/gpu-config.nix
        ];
      }
    ];

    hardware-lenovo-x1-2-in-1-gen9.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-2-in-1-gen-9.nix;
      }
    ];

    hardware-lenovo-x1-carbon-gen10.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen10.nix;
      }
    ];

    hardware-lenovo-x1-efi-uki.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen11.nix;
      }
      ./lenovo-x1/uki.nix
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

    hardware-lenovo-x1-carbon-gen13.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./lenovo-x1/definitions/x1-gen13.nix;
      }
    ];

    hardware-system76-darp11-b.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      {
        ghaf.hardware.definition = import ./system76/definitions/system76-darp11-b.nix;
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
        ghaf.hardware.passthrough.pci.autoDetectNet = true;
      }
    ];

    hardware-nvidia-jetson-orin-agx-industrial.imports = [
      inputs.self.nixosModules.jetpack
      ./jetpack/agx/orin-agx-industrial.nix
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

    imx8.imports = [
      ./imx8
      inputs.self.nixosModules.hardware-aarch64-generic
    ];

    jetpack.imports = [
      ./jetpack
      ./jetpack/nvidia-jetson-orin/optee.nix
      inputs.self.nixosModules.hardware-aarch64-generic
    ];

    polarfire.imports = [ ./polarfire ];

  };
  # keep-sorted end
}
