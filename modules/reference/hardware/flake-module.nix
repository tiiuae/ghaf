# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference hardware modules
#
{ inputs, lib, ... }:
{
  _file = ./flake-module.nix;
  # keep-sorted start skip_lines=1 block=yes newline_separated=yes by_regex=\s*nixosModules\.(.*)$ prefix_order=hardware-x86_64-workstation,jetpack
  flake.nixosModules = {
    hardware-alienware-m18-r2.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      { ghaf.hardware.definition = import ./alienware/alienware-m18.nix; }
      {
        # Hardware-specific VM configs via hardware definition
        ghaf.hardware.definition.guivm.extraModules = [
          (import ./alienware/extra-config.nix)
        ];
        ghaf.hardware.definition.netvm.extraModules = [
          (import ./alienware/net-config.nix)
        ];
      }
    ];

    hardware-demo-tower-mk1.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      { ghaf.hardware.definition = import ./demo-tower/demo-tower.nix; }
      {
        ghaf.hardware.tpm2.enable = lib.mkForce false;
        # Hardware-specific VM configs via hardware definition
        ghaf.hardware.definition.guivm.extraModules = [
          (import ./demo-tower/extra-config.nix)
        ];
      }
    ];

    hardware-intel-laptop.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      { ghaf.hardware.definition = import ./intel-laptop/intel-laptop.nix; }
      {
        ghaf.hardware = {
          passthrough = {
            pci.autoDetectGpu = true;
            pci.autoDetectNet = true;
            pci.autoDetectAudio = true;
            pciAcsOverride = {
              enable = true;
              ids = [
                "8086:15fb" # Intel Corporation Ethernet Connection (13) I219-LM (dell-latitude-7330)
                "8086:550a" # Intel Corporation Ethernet Connection (18) I219-LM (system76-darp11-b)
              ];
            };
          };
          definition.guivm.extraModules = [
            (import ./intel-laptop/extra-config.nix)
          ];
        };
      }
    ];

    hardware-lenovo-t14-amd-gen5.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      { ghaf.hardware.definition = import ./lenovo-t14-amd/definitions/gen-5.nix; }
      {
        # Hardware-specific VM configs via hardware definition
        ghaf.hardware.definition.guivm.extraModules = [
          ./lenovo-t14-amd/gpu-config.nix
        ];
      }
    ];

    hardware-tower-5080.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      { ghaf.hardware.definition = import ./tower-5080/tower-5080.nix; }
      {
        ghaf.hardware = {
          tpm2.enable = lib.mkForce false;
          # Hardware-specific VM configs via hardware definition
          definition.guivm.extraModules = [
            (import ./tower-5080/extra-config.nix)
          ];
          passthrough.pci.autoDetectNet = true;
        };
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
