# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Shared host composition for Orin GPU, display, and combined GUI passthrough.
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
      bindService = "bindGpuVm";
      description = "GPU devices";
      ownsGpu = true;
      includeDispRam = true;
    };
    dispvm = {
      optionName = "disp_vm";
      vmName = "disp-vm";
      definitionName = "dispvm";
      bindService = "bindDispVm";
      description = "display devices";
      ownsGpu = false;
      includeDispRam = false;
    };
    guivm = {
      optionName = "gui_vm";
      vmName = "gui-vm";
      definitionName = "guivm";
      bindService = "bindGuiVm";
      description = "GPU and display devices";
      ownsGpu = true;
      includeDispRam = false;
    };
  };
  roleConfig = roles.${role};
  cfg = config.ghaf.hardware.nvidia.passthroughs.${roleConfig.optionName};
  virt = config.ghaf.hardware.nvidia.virtualization;
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  dtsRoot = "${support}/device-trees";
  payloadLib = import ./default.nix { inherit lib pkgs; };
  inherit (support) bpmpPolicies;
  cap = payloadLib.capabilities.${role};
  payload = payloadLib.mkPayload cap;
  bpmpHostPath = "/dev/bpmp-host-${roleConfig.vmName}";
  board = support.boards.${if config.ghaf.hardware.nvidia.orin.somType == "nx" then "nx" else "agx"};
  configuredVmm = config.ghaf.virtualization.vmConfig.sysvms.${roleConfig.definitionName}.vmm or null;
  selectedVmm =
    if configuredVmm == null then
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm
    else
      configuredVmm;
  isCrosvm = selectedVmm == "crosvm";
  kernel = config.boot.kernelPackages.kernel;
  dtb = import ./dtb.nix {
    inherit
      lib
      pkgs
      cap
      board
      kernel
      payload
      role
      dtsRoot
      ;
  };
  crosvmOverlay = import ./crosvm-overlay.nix {
    inherit
      lib
      pkgs
      cap
      board
      kernel
      payload
      dtsRoot
      ;
  };
  guestModule = import ./guest-module.nix {
    inherit
      lib
      cap
      dtb
      crosvmOverlay
      bpmpHostPath
      payload
      ;
    dtbName = if role == "dispvm" then "tegra234-dispvm.dtb" else "tegra234-gpuvm.dtb";
    inherit (virt) sourcesPatch;
  };
  bindDevices = pkgs.writeShellScript "bind-${roleConfig.vmName}-vfio-platform" ''
    set -eu
    for device in ${lib.escapeShellArgs payload.hostDevices}; do
      echo vfio-platform > "/sys/bus/platform/devices/$device/driver_override"
      current=$(basename "$(readlink -f "/sys/bus/platform/devices/$device/driver" 2>/dev/null)" || true)
      if [ "$current" != vfio-platform ]; then
        echo "$device" > /sys/bus/platform/drivers/vfio-platform/bind
      fi
    done
  '';
in
{
  _file = ./host-module.nix;

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;
        ghaf.hardware.nvidia.virtualization.host.bpmp.consumers.${roleConfig.vmName} =
          bpmpPolicies.${
            if role == "gpuvm" then
              "compute"
            else if role == "dispvm" then
              "display"
            else
              "combined"
          };
        ghaf.virtualization.microvm.${roleConfig.definitionName}.enable = true;

        assertions = [
          {
            assertion = !config.ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains;
            message = "${roleConfig.vmName} passthrough requires the closed BPMP allow-list.";
          }
        ];

        services.udev.extraRules = ''
          KERNEL=="bpmp-host-${roleConfig.vmName}", GROUP="kvm", MODE="0660"
          SUBSYSTEM=="vfio", GROUP="kvm"
        '';

        systemd.services.${roleConfig.bindService} = {
          description = "Bind ${roleConfig.description} to vfio-platform";
          wantedBy = [ "multi-user.target" ];
          before = [ "microvm@${roleConfig.vmName}.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = bindDevices;
          };
        };

        systemd.services."microvm@${roleConfig.vmName}" = {
          requires = [ "${roleConfig.bindService}.service" ];
          after = [ "${roleConfig.bindService}.service" ];
          environment =
            lib.optionalAttrs (!isCrosvm && payload.needsDceBridge) {
              GHAF_DCE_GUEST = "1";
            }
            // {
              GHAF_BPMP_HOST = bpmpHostPath;
            };
          serviceConfig.ExecStartPre = lib.optionals isCrosvm (
            [ "${pkgs.coreutils}/bin/test -e ${bpmpHostPath}" ]
            ++ lib.optional payload.needsDceBridge "${pkgs.coreutils}/bin/test -e /dev/dce-host"
          );
        };

        ghaf.hardware.definition.${roleConfig.definitionName}.extraModules = [ guestModule ];
      }

      (lib.mkIf roleConfig.ownsGpu {
        warnings = [
          "${roleConfig.vmName} passthrough assigns the host GPU to the VM; host graphics, nvpmodel, and NVIDIA Docker are disabled."
        ];
        ghaf.profiles.graphics.enable = lib.mkForce false;
        services.nvpmodel.enable = lib.mkForce false;
        ghaf.virtualization.nvidia-docker.daemon.enable = lib.mkForce false;
        boot.blacklistedKernelModules = [
          "nvgpu"
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
          "tegra_drm"
          "host1x"
        ];
        hardware.deviceTree.overlays = [
          {
            name = "gpu_passthrough_overlay";
            dtsFile = "${dtsRoot}/gpu-vm/gpu_passthrough_overlay.dts";
          }
        ];
      })

      (lib.mkIf roleConfig.includeDispRam {
        hardware.deviceTree.dtboBuildExtraPreprocessorFlags = [ "-DGHAF_INCLUDE_DISPVM_RAM" ];
      })
    ]
  );
}
