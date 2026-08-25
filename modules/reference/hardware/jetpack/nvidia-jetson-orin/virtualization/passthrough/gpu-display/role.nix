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
      optionName = "gpu_vm";
      vmName = "gpu-vm";
      definitionName = "gpuvm";
      policyName = "compute";
      ownsGpu = true;
      description = "GPU and media passthrough to GPU VM";
    };
    dispvm = {
      optionName = "disp_vm";
      vmName = "disp-vm";
      definitionName = "dispvm";
      policyName = "display";
      ownsGpu = false;
      description = "display passthrough to Display VM";
    };
    guivm = {
      optionName = "gui_vm";
      vmName = "gui-vm";
      definitionName = "guivm";
      policyName = "combined";
      ownsGpu = true;
      description = "combined GPU and display passthrough to GUI VM";
    };
  };
  roleConfig = roles.${role};
  cfg = config.ghaf.hardware.nvidia.passthroughs.${roleConfig.optionName};
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  payload = support.passthrough.roles.${roleConfig.policyName};
  bpmpHostPath = "/dev/bpmp-host-${roleConfig.vmName}";
  board = support.boards.${if config.ghaf.hardware.nvidia.orin.somType == "nx" then "nx" else "agx"};
  kernel = config.boot.kernelPackages.kernel;
  dtsRoot = "${support}/device-trees";
  dtb = support.mkGuestDtb {
    inherit
      pkgs
      board
      kernel
      dtsRoot
      ;
    role = payload;
  };
  crosvmOverlay = support.mkCrosvmOverlay {
    inherit
      pkgs
      board
      kernel
      dtsRoot
      ;
    role = payload;
  };
  configuredVmm = config.ghaf.virtualization.vmConfig.sysvms.${roleConfig.definitionName}.vmm or null;
  selectedVmm =
    if configuredVmm == null then
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm
    else
      configuredVmm;
  isCrosvm = selectedVmm == "crosvm";
  bindService = "bind-${roleConfig.vmName}-vfio-platform.service";
in
{
  _file = ./role.nix;

  options.ghaf.hardware.nvidia.passthroughs.${roleConfig.optionName}.enable =
    lib.mkEnableOption "Orin ${roleConfig.description}";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        hardware.nvidia-jetpack.virtualization.gpuPassthroughHost.assignments.${roleConfig.vmName}.role =
          roleConfig.policyName;
        ghaf.virtualization.microvm.${roleConfig.definitionName}.enable = true;
        ghaf.hardware.definition.${roleConfig.definitionName}.extraModules = [
          (import ./guest.nix {
            inherit
              bpmpHostPath
              crosvmOverlay
              dtb
              payload
              ;
            role = roleConfig.policyName;
          })
        ];

        systemd.services."microvm@${roleConfig.vmName}" = {
          requires = [ bindService ];
          after = [ bindService ];
          environment = lib.optionalAttrs (!isCrosvm && payload.needsDceBridge) { GHAF_DCE_GUEST = "1"; } // {
            GHAF_BPMP_HOST = bpmpHostPath;
          };
          serviceConfig.ExecStartPre = lib.optionals isCrosvm (
            [ "${pkgs.coreutils}/bin/test -e ${bpmpHostPath}" ]
            ++ lib.optional payload.needsDceBridge "${pkgs.coreutils}/bin/test -e /dev/dce-host"
          );
        };
      }

      (lib.mkIf roleConfig.ownsGpu {
        services.nvpmodel.enable = lib.mkForce false;
        ghaf.profiles.graphics.enable = lib.mkForce false;
        ghaf.virtualization.nvidia-docker.daemon.enable = lib.mkForce false;
      })

      (lib.mkIf (role == "guivm" && !isCrosvm) {
        ghaf.hardware.passthrough.usb.guivmDeny = [
          {
            vendorId = "046d";
            productId = "c52b";
            description = "Logitech Unifying Receiver: evdev-only with the QEMU rollback";
          }
        ];
      })
    ]
  );
}
