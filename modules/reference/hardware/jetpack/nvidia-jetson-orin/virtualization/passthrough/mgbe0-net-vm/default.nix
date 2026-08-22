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
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  configuredNetVmVmm = config.ghaf.virtualization.vmConfig.sysvms.netvm.vmm or null;
  netVmVmm =
    if configuredNetVmVmm == null then
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm
    else
      configuredNetVmVmm;
  isCrosvm = netVmVmm == "crosvm";

  stopCrosvmNetVm = pkgs.writeShellScript "stop-crosvm-net-vm" ''
    set -u

    pid="''${MAINPID:-}"
    if [ -z "$pid" ]; then
      echo "Crosvm net-vm has no MAINPID; nothing to stop"
      exit 0
    fi

    # Crosvm's powerbtn control command is not supported on AArch64. Ask the
    # guest to enter poweroff.target through GIVC instead, then keep ExecStop
    # active until Crosvm exits. This lets the MGBE driver quiesce DMA before
    # VFIO tears down the SMMU mappings.
    echo "Starting poweroff target for Crosvm net-vm"
    ${pkgs.givc-cli}/bin/givc-cli ${
      lib.replaceStrings [ "/run" ] [ "/etc" ] config.ghaf.givc.cliArgs
    } start service --vm net-vm poweroff.target &

    echo "Waiting for Crosvm net-vm with PID=$pid to stop"
    while kill -0 "$pid" 2>/dev/null; do
      sleep 1
    done
    echo "Crosvm net-vm with PID=$pid stopped"
  '';

  mgbe0Overlay =
    pkgs.buildPackages.runCommand "mgbe0-crosvm-overlay.dtbo"
      {
        nativeBuildInputs = [ pkgs.buildPackages.dtc ];
      }
      ''
        host_dtb=${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}
        host_node=/bus@0/ethernet@6800000

        check_bpmp_ids() {
          property="$1"
          expected="$2"
          values="$(fdtget -t i "$host_dtb" "$host_node" "$property")"
          set -- $values
          if [ "$#" -eq 0 ] || [ $(( $# % 2 )) -ne 0 ]; then
            echo "malformed $property in pinned AGX device tree" >&2
            exit 1
          fi
          ids=""
          while [ "$#" -gt 0 ]; do
            shift
            ids="''${ids:+$ids }$1"
            shift
          done
          if [ "$ids" != "$expected" ]; then
            echo "$property BPMP IDs drifted: expected '$expected', got '$ids'" >&2
            exit 1
          fi
        }

        test "$(fdtget -t s "$host_dtb" "$host_node" compatible)" = "nvidia,tegra234-mgbe"
        test "$(fdtget -t s "$host_dtb" "$host_node" phy-mode)" = "10gbase-r"
        check_bpmp_ids clocks "357 361 369 373 374 375 376 377 379 380 381 378 248"
        check_bpmp_ids resets "46 45 47"
        check_bpmp_ids power-domains "18"

        dtc -@ -I dts -O dtb -o "$out" ${./mgbe0-crosvm-overlay.dts}
      '';

  prepareMgbe0Overlay = pkgs.writeShellApplication {
    name = "prepare-mgbe0-crosvm-overlay";
    runtimeInputs = with pkgs; [
      coreutils
      dtc
      findutils
      gnugrep
    ];
    text = ''
      set -euo pipefail

      live_root=/sys/firmware/devicetree/base
      live_fdt=/sys/firmware/fdt
      output=/run/mgbe0-net-vm.dtbo
      mapfile -d "" nodes < <(find "$live_root" -type d -name 'ethernet@6800000' -print0)
      if [ "''${#nodes[@]}" -ne 1 ]; then
        echo "expected one live ethernet@6800000 node, found ''${#nodes[@]}" >&2
        exit 1
      fi
      node="''${nodes[0]}"
      node_path="/''${node#"$live_root"/}"
      if ! tr '\0' '\n' < "$node/compatible" | grep -Fxq 'nvidia,tegra234-mgbe'; then
        echo "live $node_path is not compatible with nvidia,tegra234-mgbe" >&2
        exit 1
      fi

      check_bpmp_ids() {
        local property="$1" expected="$2" values ids=""
        values="$(fdtget -t i "$live_fdt" "$node_path" "$property")"
        read -r -a cells <<< "$values"
        if [ "''${#cells[@]}" -eq 0 ] || [ $(( ''${#cells[@]} % 2 )) -ne 0 ]; then
          echo "malformed live $property on $node_path" >&2
          exit 1
        fi
        for ((index = 1; index < ''${#cells[@]}; index += 2)); do
          ids="''${ids:+$ids }''${cells[index]}"
        done
        if [ "$ids" != "$expected" ]; then
          echo "live $property BPMP IDs drifted: expected '$expected', got '$ids'" >&2
          exit 1
        fi
      }

      check_bpmp_ids clocks "357 361 369 373 374 375 376 377 379 380 381 378 248"
      check_bpmp_ids resets "46 45 47"
      check_bpmp_ids power-domains "18"

      install -m 0644 ${mgbe0Overlay} "$output"
      if [ -e "$node/mac-address" ]; then
        if [ "$(stat -c %s "$node/mac-address")" -ne 6 ]; then
          echo "live mac-address on $node_path is not six bytes" >&2
          exit 1
        fi
        read -r -a mac_bytes <<< "$(od -An -v -t x1 "$node/mac-address")"
        if [ "''${#mac_bytes[@]}" -ne 6 ]; then
          echo "could not decode live mac-address on $node_path" >&2
          exit 1
        fi
        fdtput -t bx "$output" /fragment@0/__overlay__/ethernet mac-address "''${mac_bytes[@]}"
      fi
    '';
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable =
    lib.mkEnableOption "MGBE0 (ethernet@6800000) passthrough to the Net-VM on NVIDIA Orin";

  config = lib.mkIf cfg.enable {
    # The guest can only bring MGBE0 up through the BPMP host proxy.
    ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;

    ghaf.hardware.nvidia.virtualization.host.bpmp.allow = {
      # MGBE0 (ethernet@6800000) clocks, resets, power domain -- raw BPMP ids
      # read from the device's live DT (not TEGRA234_CLK_* macros; NVIDIA's DT
      # has drifted from mainline). "clock not allowed" denials at guest boot are
      # the boundary working, not a bug -- see bpmp-host-proxy.c.
      clocks = [
        357
        361
        369
        373
        374
        375
        376
        377
        378
        379
        380
        381
        248
        # MGBE0's "tx" (374) is fed by a PLL chain that clk_prepare() walks in
        # full, so every link needs allowing or the child fails: the guest logs
        # "Failed to prepare clk 'tx': -5" and tegra-mgbe probes at -5, while the
        # host logs "bpmp-host: Warning, clock not allowed for: <id>, command: 7".
        # Allowing only part of the chain just moves the denial to the next link
        # (seen going 319 -> 367). All of these are gigabit-ethernet dedicated,
        # so the boundary stays ethernet-scoped: host-critical display/memory
        # PLLs stay denied, and the MGBE1/2/3 instances are deliberately not
        # listed since only MGBE0 is passed through.
        319 # PLLGBE
        320 # PLLGBE_HPS
        366 # MGBES_APP
        367 # UPHY_GBE_PLL2_TX_REF
        368 # UPHY_GBE_PLL2_XDIG
        # mgbe0_app (380) does not hang off the GBE PLLs at all: it is clocked
        # at 480 MHz from the USB/UTMI tree, so clk_prepare walks
        # mgbe0_app -> utmipll_clkout480 -> utmip_pll -> osc/clk_m. Every one of
        # these is shared with host USB, so bpmp-host-proxy.c also lists them in
        # protected_clk_roots: net-vm may enable and read them, but
        # disable/set_rate/set_parent stay denied, so a guest cannot pull the
        # clock out from under the host's USB (keyboard, net-vm's own NIC).
        103 # UTMIP_PLL
        292 # UTMIPLL_CLKOUT480
        91 # OSC
        14 # CLK_M
        # ptp-ref (381) hangs off the PLLREFE tree rather than the USB one, so
        # it needs its own two ancestors. PLLREFE is a shared reference PLL
        # (PCIe/UPHY use it too), hence protected_clk_roots as well.
        288 # PLLREFE_VCOOUT
        327 # PLLREFE_VCOOUT_GATED
      ];
      resets = [
        45
        46
        47
      ];
      powerDomains = [ 18 ];
    };

    services.udev.extraRules = ''
      # The VMM opens /dev/bpmp-host as user microvm, group kvm. The character
      # device is otherwise 0600 root:root.
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
    systemd.services."microvm@net-vm" = {
      requires = lib.optionals isCrosvm [ "prepareMgbe0CrosvmOverlay.service" ];
      after = [ "bindMgbe0.service" ] ++ lib.optionals isCrosvm [ "prepareMgbe0CrosvmOverlay.service" ];
      serviceConfig = lib.mkIf isCrosvm {
        TimeoutStopSec = "30";
        ExecStop = lib.mkForce [
          ""
          "+${stopCrosvmNetVm}"
        ];
      };
    };

    systemd.services.prepareMgbe0CrosvmOverlay = lib.mkIf isCrosvm {
      description = "Prepare the live MGBE0 device-tree overlay for Crosvm";
      before = [ "microvm@net-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe prepareMgbe0Overlay;
      };
    };

    ghaf.hardware.definition.netvm.extraModules = [
      (
        { config, pkgs, ... }:
        let
          guestKernelVersion = config.boot.kernelPackages.kernel.version;
          quiesceMgbe0 = pkgs.writeShellScript "quiesce-mgbe0" ''
            set -eu

            net_path=/sys/bus/platform/devices/c0000000.ethernet/net
            if [ ! -d "$net_path" ]; then
              echo "MGBE0 network-device path is missing: $net_path" >&2
              exit 1
            fi

            found=0
            for path in "$net_path"/*; do
              [ -e "$path" ] || continue
              found=1
              interface="''${path##*/}"
              echo "Quiescing MGBE0 interface $interface"
              ${pkgs.iproute2}/bin/ip link set dev "$interface" down
            done

            if [ "$found" -eq 0 ]; then
              echo "No MGBE0 network interface found under $net_path" >&2
              exit 1
            fi
          '';
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
              patch = "${support}/patches/linux/0001-dwmac-tegra-fixed-stream-id.patch";
            }
            {
              name = "bpmp-virt proxy drivers";
              patch = virt.sourcesPatch;
            }
            {
              name = "bpmp-virt core hooks";
              patch =
                if lib.versionAtLeast guestKernelVersion "6.12" then
                  "${support}/patches/linux/bpmp/0001-bpmp-virt-hooks-6.12.patch"
                else
                  "${support}/patches/linux/bpmp/0001-bpmp-virt-hooks.patch";
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
          # still has -device vfio-platform (removed upstream in 10.2). It also
          # emits MGBE0's guest DT node.
          ghaf.virtualization.qemu.package = lib.mkIf (config.microvm.hypervisor == "qemu") (
            lib.mkForce pkgs.ghaf-qemu-bpmp
          );
          microvm.qemu.extraArgs = lib.mkIf (config.microvm.hypervisor == "qemu") [
            "-device"
            # Keep the proven, bounded QEMU workaround. Crosvm does not get
            # startup rearm without trace evidence of the same IRQ wedge.
            "vfio-platform,host=6800000.ethernet,startup-rearm=on"
          ];

          microvm.devices = lib.mkIf (config.microvm.hypervisor == "crosvm") [
            {
              bus = "platform";
              path = "6800000.ethernet";
              crosvm = {
                dtSymbol = "mgbe0";
                iommu = "off";
              };
            }
          ];
          microvm.crosvm.deviceTreeOverlays = lib.mkIf (config.microvm.hypervisor == "crosvm") [
            "/run/mgbe0-net-vm.dtbo"
          ];
          microvm.crosvm.extraArgs = lib.mkIf (config.microvm.hypervisor == "crosvm") [
            "--nvidia-bpmp-host"
            "/dev/bpmp-host"
          ];

          # Crosvm removes the VFIO mappings as soon as the guest exits. The
          # MGBE controller must therefore stop DMA before poweroff; otherwise
          # it continues writing through stale mappings and faults the host
          # SMMU. Stop this service before GIVC and the network stack so the
          # driver's ndo_stop path runs while the guest is still operational.
          systemd.services.quiesce-mgbe0 = lib.mkIf (config.microvm.hypervisor == "crosvm") {
            description = "Quiesce MGBE0 before Crosvm shutdown";
            wantedBy = [ "multi-user.target" ];
            after = [
              "givc-net-vm.service"
              "network.target"
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
              ExecStop = quiesceMgbe0;
            };
          };
        }
      )
    ];
  };
}
