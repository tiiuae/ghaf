# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Compute GPU, host1x, and media passthrough to gpu-vm.
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.gpu_vm;
in
{
  _file = ./default.nix;

  imports = [ (import ../payload/host-module.nix { role = "gpuvm"; }) ];

  options.ghaf.hardware.nvidia.passthroughs.gpu_vm = {
    enable = lib.mkEnableOption "Tegra234 GPU and engine passthrough to gpu-vm on NVIDIA Orin";

    containerRuntime = {
      enable = lib.mkEnableOption "Docker with NVIDIA CDI devices in gpu-vm";
      addGhafUserToDockerGroup = lib.mkEnableOption "root-equivalent Docker access for the ghaf user in gpu-vm";
    };

    partitionManager = {
      enable = lib.mkEnableOption "the cooperative CUDA Green Context job manager in gpu-vm";

      plugins = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Trusted Nix-built workload plugins loaded by gpu-partition-manager.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.definition.gpuvm.extraModules = [
      {
        ghaf.virtualization.gpuPartitionManager = {
          inherit (cfg.partitionManager) enable plugins;
        };
        ghaf.virtualization.gpuContainerRuntime = {
          inherit (cfg.containerRuntime) enable addGhafUserToDockerGroup;
        };
      }
    ];
  };
}
