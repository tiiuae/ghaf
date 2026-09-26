# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ role }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  roles = {
    gpuvm = {
      option = "gpu_vm";
      vm = "gpu-vm";
      definition = "gpuvm";
      policy = "compute";
      ownsGpu = true;
    };
    dispvm = {
      option = "disp_vm";
      vm = "disp-vm";
      definition = "dispvm";
      policy = "display";
      ownsGpu = false;
    };
    guivm = {
      option = "gui_vm";
      vm = "gui-vm";
      definition = "guivm";
      policy = "combined";
      ownsGpu = true;
    };
  };
  inherit (roles.${role})
    option
    vm
    definition
    policy
    ownsGpu
    ;
  cfg = config.ghaf.hardware.nvidia.passthroughs.${option};
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  payload = support.passthrough.roles.${policy};
  bpmpHostPath = "/dev/bpmp-host-${vm}";
  board = support.boards.${if config.ghaf.hardware.nvidia.orin.somType == "nx" then "nx" else "agx"};
  dtb = support.mkGuestDtb {
    inherit pkgs board;
    kernel = config.boot.kernelPackages.kernel;
    dtsRoot = "${support}/device-trees";
    role = payload;
  };
  bindService = "bind-${vm}-vfio-platform.service";
in
{
  _file = ./role.nix;

  options.ghaf.hardware.nvidia.passthroughs.${option} = {
    enable = lib.mkEnableOption "Orin ${policy} GPU/display passthrough";
  }
  // lib.optionalAttrs (role == "gpuvm") {
    containerRuntime = {
      enable = lib.mkEnableOption "Docker with NVIDIA CDI devices in GPU VM";
      addGhafUserToDockerGroup = lib.mkEnableOption "root-equivalent Docker access for the ghaf user in GPU VM";
    };
    partitionManager = {
      enable = lib.mkEnableOption "the cooperative CUDA Green Context job manager in GPU VM";
      plugins = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Trusted Nix-built workload plugins loaded by gpu-partition-manager.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        hardware.nvidia-jetpack.virtualization.gpuPassthroughHost.assignments.${vm}.role = policy;
        ghaf.virtualization.microvm.${definition}.enable = true;
        ghaf.hardware.definition.${definition}.extraModules = [
          (import ./guest.nix {
            inherit
              dtb
              payload
              policy
              ;
          })
        ]
        ++ lib.optional (role == "gpuvm") {
          ghaf.virtualization.gpuPartitionManager = {
            inherit (cfg.partitionManager) enable plugins;
          };
          ghaf.virtualization.gpuContainerRuntime = {
            inherit (cfg.containerRuntime) enable addGhafUserToDockerGroup;
          };
        };

        systemd.services."microvm@${vm}" = {
          requires = [ bindService ];
          after = [ bindService ];
          environment = {
            GHAF_BPMP_HOST = bpmpHostPath;
          }
          // lib.optionalAttrs payload.needsDceBridge { GHAF_DCE_GUEST = "1"; };
        };
      }

      (lib.mkIf ownsGpu {
        services.nvpmodel.enable = lib.mkForce false;
        ghaf.profiles.graphics.enable = lib.mkForce false;
        ghaf.virtualization.nvidia-docker.daemon.enable = lib.mkForce false;
      })
    ]
  );
}
