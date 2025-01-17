# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.virtualization.host.bpmp;
in
{
  options.ghaf.hardware.nvidia.virtualization.host.bpmp.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable virtualization host support for NVIDIA Orin

      This option is an implementation level detail and is toggled automatically
      by modules that need it. Manually enabling this option is not recommended in
      release builds.
    '';
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [ (import ./overlays/qemu) ];

    boot.kernelPatches = [
      {
        name = "Bpmp virtualization host kernel configuration";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          VFIO_PLATFORM = yes;
          TEGRA_BPMP_HOST_PROXY = yes;
        };
      }
    ];

    # Enable hardware.deviceTree for handle host dtb overlays
    hardware.deviceTree.enable = true;

    # Apply the device tree overlay only to tegra234-p3701-host-passthrough.dtb
    hardware.deviceTree.overlays = [
      {
        name = "bpmp_host_overlay";
        dtsFile = ./bpmp_host_overlay.dts;
      }
      {
        name = "gpu_passthrough_overlay";
        dtsFile = ./gpu_passthrough_overlay.dts;

        filter = "tegra234-p3737-0000+p3701-0000.dtb";
      }
    ];


    # TODO: Consider are these really needed, maybe add only in debug builds?
    environment.systemPackages = with pkgs; [
      qemu_kvm
      dtc
    ];
  };
}
