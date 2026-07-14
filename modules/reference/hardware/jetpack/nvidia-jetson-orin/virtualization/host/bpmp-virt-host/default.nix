# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./default.nix;

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
    ghaf.hardware.nvidia.virtualization.enable = true;

    # No QEMU override here. The BPMP guest bridge device is needed only by the
    # VM that receives a BPMP-backed passthrough device, and
    # ghaf.virtualization.qemu.package is consumed by every VM
    # (modules/microvm/common/vm-qemu.nix). The patched QEMU opens /dev/bpmp-host
    # unconditionally in create_virtio_devices(), so admin-vm and gui-vm must not
    # get it. The consuming module sets microvm.qemu.package in its own scope.

    boot.kernelPatches = [
      {
        name = "Bpmp virtualization host kernel configuration";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          VFIO_PLATFORM = yes;
          TEGRA_BPMP_HOST_PROXY = yes;
        };
      }
    ];

    # The bpmp_host_proxy node used to be injected by a kernel patch against
    # tegra234-soc-base.dtsi. A DT overlay does the same without carrying a patch
    # against NVIDIA's device trees.
    hardware.deviceTree.enable = true;
    hardware.deviceTree.overlays = [
      {
        name = "bpmp_host_overlay";
        dtsFile = ./bpmp_host_overlay.dts;
      }
    ];

    environment.systemPackages = [ pkgs.dtc ];
  };
}
