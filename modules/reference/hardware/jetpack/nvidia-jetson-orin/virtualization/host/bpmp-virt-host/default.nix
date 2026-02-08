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
    # TODO: another stray overlay that should be centralized.
    nixpkgs.overlays = [ (import ./overlays/qemu) ];

    boot.kernelPatches = [
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
        structuredExtraConfig = with lib.kernel; {
          VFIO_PLATFORM = yes;
          TEGRA_BPMP_HOST_PROXY = yes;
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
