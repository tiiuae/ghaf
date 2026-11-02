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
        # The host owns this machine's panel backlight, not the GUI VM driving
        # the display, so brightness keys must be forwarded. This turns on all
        # three pieces: guest forwarder, virtio-serial port, host receiver.
        ghaf.global-config.features.brightness = {
          enable = true;
          hostBacklight = "nvidia_wmi_ec_backlight";
        };

        # Hardware-specific VM configs via hardware definition
        ghaf.hardware.definition.guivm.extraModules = [
          (import ./alienware/extra-config.nix)
        ];
        ghaf.hardware.definition.netvm.extraModules = [
          (import ./alienware/net-config.nix)
        ];

        # Suspend does not resume on this board.
        ghaf.services.power-manager.suspend.enable = false;
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
        ghaf.services.performance.host.thermalLimitMode = "enabled";
      }
    ];

    hardware-intel-laptop.imports = [
      inputs.self.nixosModules.hardware-x86_64-workstation
      { ghaf.hardware.definition = import ./intel-laptop/intel-laptop.nix; }
      (import ./intel-laptop/extra-config-host.nix)
      {
        ghaf.hardware = {
          passthrough = {
            pci = {
              autoDetectGpu = true;
              autoDetectNet = true;
              autoDetectAudio = true;
            };
            pciAcsOverride = {
              enable = true;
              ids = [
                "8086:15fb" # Intel Corporation Ethernet Connection (13) I219-LM (dell-latitude-7330)
                "8086:550a" # Intel Corporation Ethernet Connection (18) I219-LM (system76-darp11-b)
              ];
            };
          };
          definition.guivm.extraModules = [
            (import ./intel-laptop/extra-config-guivm.nix)
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
        ghaf.services.performance.host.thermalLimitMode = "enabled";
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
      ./jetpack/nvidia-jetson-orin/optee/optee.nix
      inputs.self.nixosModules.hardware-aarch64-generic
    ];

    jetpack-orin-gpu-partitioning.imports =
      map
        (
          role:
          import ./jetpack/nvidia-jetson-orin/virtualization/passthrough/gpu-display/role.nix {
            inherit role;
          }
        )
        [
          "gpuvm"
          "dispvm"
        ];

    polarfire.imports = [ ./polarfire ];

  };
  # keep-sorted end
}
