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

  ids = map toString;
  allow = config.ghaf.hardware.nvidia.virtualization.host.bpmp.allow;

  # BPMP host-proxy allow-list. The proxy forwards a guest's clock/reset/power
  # requests to the real BPMP ONLY for the ids listed here (bpmp-host-proxy.c
  # gates MRQ_CLK, MRQ_RESET and MRQ_PG against these three properties);
  # everything else is refused.
  #
  # This is a safety boundary. A guest kernel that could reach arbitrary clocks
  # would switch off ones the host needs -- its eMMC controller among them --
  # and wedge the host. Keep this list to exactly the resources of the devices
  # actually passed through. Do NOT widen it to "everything"; see
  # ghaf.hardware.nvidia.virtualization.bpmpAllowAllDomains.
  #
  # EXPECTED, and not a bug: the host proxy logs a stream of
  #   "bpmp-host: Warning, clock not allowed for: <id>, with command: <n>"
  # at guest boot. Those are the boundary working. A passed-through guest's
  # clock framework probes rates and re-enables parent PLLs that are already
  # on at the host; both are refused and neither is needed by the passthrough
  # devices this list was built for. Do not add the probed ids to "fix" the
  # warnings: that reopens the path to clocks the guest could later disable.
  bpmpHostOverlay = pkgs.writeText "bpmp_host_overlay.dts" ''
    /dts-v1/;
    /plugin/;
    / {
        overlay-name = "BPMP host proxy allow-list";
        compatible = "nvidia,tegra234";
        fragment@0 {
            target-path = "/";
            __overlay__ {
                bpmp_host_proxy: bpmp_host_proxy {
                    compatible = "nvidia,bpmp-host-proxy";
                    allowed-clocks = <${lib.concatStringsSep " " (ids allow.clocks)}>;
                    allowed-resets = <${lib.concatStringsSep " " (ids allow.resets)}>;
                    allowed-power-domains = <${lib.concatStringsSep " " (ids allow.powerDomains)}>;
                    status = "okay";
                };
            };
        };
    };
  '';
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

  options.ghaf.hardware.nvidia.virtualization.host.bpmp.allow = {
    clocks = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
      apply = lib.unique;
      description = "Raw BPMP clock ids the host proxy forwards for passed-through devices (union across enabled passthroughs).";
    };
    resets = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
      apply = lib.unique;
      description = "Raw BPMP reset ids allowed for passed-through devices.";
    };
    powerDomains = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
      apply = lib.unique;
      description = "Raw BPMP power-domain ids allowed for passed-through devices.";
    };
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
        dtsFile = bpmpHostOverlay;
      }
    ];

    environment.systemPackages = [ pkgs.dtc ];
  };
}
