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

    # in practice this configures both host and guest kernel becaue we use only one kernel in the whole system§
    boot.kernelPatches = [

      # dts patches are temporary -- we move towards overlays, not patches
      {
        name = "Bpmp virtualization host proxy device tree";
        patch = ./patches/0001-bpmp-host-proxy-dts.patch;
      }
      {
        name = "Bpmp virtualization host uarta device tree";
        patch = ./patches/0002-bpmp-host-uarta-dts.patch;
      }
      {
        name = "Bpmp virtualization host kernel configuration";
        patch = null;
        extraStructuredConfig = {
          VFIO_PLATFORM = lib.kernel.yes;
          TEGRA_BPMP_HOST_PROXY = lib.kernel.yes;
          TEGRA_BPMP_GUEST_PROXY = lib.kernel.yes;
        };
      }
    ];

    # TODO: Consider are these really needed, maybe add only in debug builds?
    environment.systemPackages = with pkgs; [
      qemu_kvm
      dtc
    ];
  };
}
