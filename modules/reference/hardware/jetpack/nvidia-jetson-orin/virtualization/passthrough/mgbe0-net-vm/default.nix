# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass the AGX Orin's on-SoC ethernet (MGBE0, ethernet@6800000) to net-vm.
#
#   data     vfio-platform hands the MAC's MMIO + IRQs to the guest; MGBE0 is
#            alone in its IOMMU group, so VFIO takes it cleanly.
#   control  the node's clocks/resets/power-domain are <&bpmp ...> refs and the
#            guest has no BPMP, so the guest tegra_bpmp is redirected (via the
#            `virtual-pa` prop on its /bpmp node) to a QEMU bridge that forwards
#            to /dev/bpmp-host. See bpmp-virt-common.
#
# QEMU emits the guest DT (a dynamic sysbus device with no FDT binding aborts
# `virt`); there is no hand-written -dtb.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm;
  virt = config.ghaf.hardware.nvidia.virtualization;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable =
    lib.mkEnableOption "MGBE0 (ethernet@6800000) passthrough to the Net-VM on NVIDIA Orin";

  config = lib.mkIf cfg.enable {
    # The guest can only bring MGBE0 up through the BPMP host proxy.
    ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;

    services.udev.extraRules = ''
      # QEMU opens /dev/bpmp-host in instance_init, and microvm.nix runs it as
      # user microvm, group kvm. The char device is otherwise 0600 root:root.
      KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"

      # vfio group nodes for the passed-through platform device.
      SUBSYSTEM=="vfio", GROUP="kvm"
    '';

    # Stop the host binding MGBE0 by blacklisting its drivers, NOT by dummying
    # the DT compatible: QEMU's vfio-platform reads of_node/compatible to pick
    # the FDT emitter, so "nvidia,dummy" makes the nvidia,tegra234-mgbe binding
    # miss and QEMU exits ("can not be dynamically instantiated"). Leaving the
    # node pristine also dodges the nvethernet .remove that poisons a rebind.
    boot.blacklistedKernelModules = [
      "nvethernet"
      "dwmac-tegra"
    ];

    # Bind MGBE0 to vfio-platform before net-vm starts.
    systemd.services.bindMgbe0 = {
      description = "Bind MGBE0 (6800000.ethernet) to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@net-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = "${pkgs.bash}/bin/bash -c \"echo vfio-platform > /sys/bus/platform/devices/6800000.ethernet/driver_override\"";
        ExecStart = "${pkgs.bash}/bin/bash -c \"echo 6800000.ethernet > /sys/bus/platform/drivers/vfio-platform/bind\"";
      };
    };
    systemd.services."microvm@net-vm".after = [ "bindMgbe0.service" ];

    ghaf.hardware.definition.netvm.extraModules = [
      (
        { config, pkgs, ... }:
        let
          guestKernelVersion = config.boot.kernelPackages.kernel.version;
        in
        {
          # v6.12 hardcodes MGBE0's SMMU stream id (0x6); v6.13+ reads it from an
          # iommu_fwspec the QEMU virt guest lacks (probe -EINVALs). v6.12 also
          # carries the Oct-2024 serdes bring-up fix (1cff6ff30) that v6.6 lacks.
          boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;

          # MANDATORY, independent of the host proxy's allow-list. At
          # late_initcall the guest runs clk_disable_unused() /
          # genpd_power_off_unused(); through the guest proxy those reach the REAL
          # BPMP and switch off clocks the host needs (e.g. its eMMC), wedging it.
          # These params stop the guest ever issuing the disables. See
          # bpmp-host-proxy.c.
          boot.kernelParams = [
            "clk_ignore_unused"
            "pd_ignore_unused"
          ];

          boot.kernelPatches = [
            {
              # 6.12.95 backported commit 426046e2d, so dwmac-tegra reads MGBE0's
              # SMMU stream id from DT and -EINVALs when a passthrough guest has
              # no IOMMU. Fall back to the fixed stream id 6.
              name = "dwmac-tegra fixed stream id";
              patch = ./0001-dwmac-tegra-fixed-stream-id.patch;
            }
            {
              # stmmac_mac_link_up() has no SPEED_10000 case in its generic
              # branch, so it returns before re-enabling the MAC: eth1 keeps
              # carrier but passes no traffic after a cable unplug. Mainline
              # bug, not passthrough-specific; drop this once it lands upstream.
              name = "stmmac enable mac on 10gbase-r link up";
              patch = ./0002-stmmac-enable-mac-on-10gbase-r-link-up.patch;
            }
            {
              name = "bpmp-virt proxy drivers";
              patch = virt.sourcesPatch;
            }
            {
              name = "bpmp-virt core hooks";
              patch =
                if lib.versionAtLeast guestKernelVersion "6.12" then
                  ../../common/bpmp-virt-common/patches/0001-bpmp-virt-hooks-6.12.patch
                else
                  ../../common/bpmp-virt-common/patches/0001-bpmp-virt-hooks.patch;
            }
            {
              name = "bpmp guest proxy kernel configuration";
              patch = null;
              structuredExtraConfig = with lib.kernel; {
                # tegra_bpmp_match[] only registers "nvidia,tegra186-bpmp" when one
                # of the 186/194/234 SoCs is enabled, and TEGRA_BPMP itself depends
                # on TEGRA_HSP_MBOX and TEGRA_IVC.
                ARCH_TEGRA = yes;
                ARCH_TEGRA_234_SOC = yes;
                TEGRA_HSP_MBOX = yes;
                TEGRA_IVC = yes;
                TEGRA_BPMP = yes;
                TEGRA_BPMP_GUEST_PROXY = yes;
                TEGRA_BPMP_HOST_PROXY = no;
                # BPMP clock/reset/power-domain providers the MGBE0 node refers to.
                CLK_TEGRA_BPMP = yes;
                RESET_TEGRA_BPMP = yes;
                PM_GENERIC_DOMAINS = yes;
                # The ethernet driver and the AGX devkit's PHY (Aquantia AQR113C,
                # identified on the host in Task 1).
                STMMAC_ETH = yes;
                STMMAC_PLATFORM = yes;
                DWMAC_TEGRA = yes;
                AQUANTIA_PHY = yes;
              };
            }
          ];

          # Only this VM gets the QEMU that has the BPMP bridge and, crucially,
          # still has -device vfio-platform (removed upstream in 10.2). That QEMU
          # also carries the FDT binding that emits MGBE0's guest node.
          ghaf.virtualization.qemu.package = lib.mkForce pkgs.ghaf-qemu-bpmp;

          # Hand MGBE0 to the guest. QEMU emits the ethernet DT node itself (from
          # the nvidia,tegra234-mgbe binding in sysbus-fdt.c); there is no -dtb.
          microvm.qemu.extraArgs = [
            "-device"
            "vfio-platform,host=6800000.ethernet"
          ];
        }
      )
    ];
  };
}
