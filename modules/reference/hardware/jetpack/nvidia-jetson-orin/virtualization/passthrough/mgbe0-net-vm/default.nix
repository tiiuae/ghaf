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
#            to net-vm's dedicated BPMP host proxy. See bpmp-virt-common.
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
  isCrosvm =
    (
      if configuredNetVmVmm == null then
        config.ghaf.virtualization.vmConfig.defaultSysVmVmm
      else
        configuredNetVmVmm
    ) == "crosvm";
  mgbe0Policy = support.bpmpPolicies.mgbe0;
  mgbe0 = support.passthrough.mgbe0;
  mgbe0DevicePath = "/sys/bus/platform/devices/${mgbe0.sysfsName}";
  mgbe0BpmpIds = mgbe0Policy.device;
  ids = values: lib.concatStringsSep " " (map toString values);
  bpmpRefs = values: lib.concatMapStringsSep ", " (value: "<&bpmp ${toString value}>") values;
  mgbe0OverlayDts = pkgs.replaceVars "${support}/device-trees/mgbe0/mgbe0-crosvm-overlay.dts" {
    bpmpClocks = bpmpRefs mgbe0BpmpIds.clocks;
    bpmpResets = bpmpRefs mgbe0BpmpIds.resets;
    bpmpPowerDomains = bpmpRefs mgbe0BpmpIds.powerDomains;
  };

  mgbe0Overlay =
    pkgs.buildPackages.runCommand "mgbe0-crosvm-overlay.dtbo"
      {
        nativeBuildInputs = [ pkgs.buildPackages.dtc ];
      }
      ''
        host_dtb=${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}
        host_node=${lib.escapeShellArg mgbe0.nodePath}

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

        test "$(fdtget -t s "$host_dtb" "$host_node" compatible)" = ${lib.escapeShellArg mgbe0.compatible}
        test "$(fdtget -t s "$host_dtb" "$host_node" phy-mode)" = "10gbase-r"
        check_bpmp_ids clocks ${lib.escapeShellArg (ids mgbe0BpmpIds.clocks)}
        check_bpmp_ids resets ${lib.escapeShellArg (ids mgbe0BpmpIds.resets)}
        check_bpmp_ids power-domains ${lib.escapeShellArg (ids mgbe0BpmpIds.powerDomains)}

        dtc -@ -I dts -O dtb -o "$out" ${mgbe0OverlayDts}
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
      temporary="$(mktemp --tmpdir=/run .mgbe0-net-vm.dtbo.XXXXXX)"
      trap 'rm -f "$temporary"' EXIT
      mapfile -d "" nodes < <(find "$live_root" -type d -name ${lib.escapeShellArg mgbe0.nodeName} -print0)
      if [ "''${#nodes[@]}" -ne 1 ]; then
        echo "expected one live ${mgbe0.nodeName} node, found ''${#nodes[@]}" >&2
        exit 1
      fi
      node="''${nodes[0]}"
      node_path="/''${node#"$live_root"/}"
      if ! tr '\0' '\n' < "$node/compatible" | grep -Fxq ${lib.escapeShellArg mgbe0.compatible}; then
        echo "live $node_path is not compatible with ${mgbe0.compatible}" >&2
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

      check_bpmp_ids clocks ${lib.escapeShellArg (ids mgbe0BpmpIds.clocks)}
      check_bpmp_ids resets ${lib.escapeShellArg (ids mgbe0BpmpIds.resets)}
      check_bpmp_ids power-domains ${lib.escapeShellArg (ids mgbe0BpmpIds.powerDomains)}

      install -m 0644 ${mgbe0Overlay} "$temporary"
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
        fdtput -t bx "$temporary" /fragment@0/__overlay__/ethernet mac-address "''${mac_bytes[@]}"
      fi
      mv "$temporary" "$output"
      trap - EXIT
    '';
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable =
    lib.mkEnableOption "MGBE0 (${mgbe0.nodeName}) passthrough to the Net-VM on NVIDIA Orin";

  config = lib.mkIf cfg.enable {
    # The guest can only bring MGBE0 up through the BPMP host proxy.
    ghaf.hardware.nvidia.virtualization.host.bpmp.enable = true;

    ghaf.hardware.nvidia.virtualization.host.bpmp.consumers.net-vm = mgbe0Policy.proxy;

    services.udev.extraRules = ''
      # The VMM opens net-vm's BPMP proxy as user microvm, group kvm. The
      # character device is otherwise 0600 root:root.
      KERNEL=="bpmp-host-net-vm", GROUP="kvm", MODE="0660"

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
      description = "Bind MGBE0 (${mgbe0.sysfsName}) to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@net-vm.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = "${pkgs.bash}/bin/bash -c \"echo vfio-platform > ${mgbe0DevicePath}/driver_override\"";
        ExecStart = "${pkgs.bash}/bin/bash -c \"echo ${mgbe0.sysfsName} > /sys/bus/platform/drivers/vfio-platform/bind\"";
      };
    };
    systemd.services."microvm@net-vm" = {
      requires = lib.optionals isCrosvm [ "prepareMgbe0CrosvmOverlay.service" ];
      after = [ "bindMgbe0.service" ] ++ lib.optionals isCrosvm [ "prepareMgbe0CrosvmOverlay.service" ];
      environment.GHAF_BPMP_HOST = "/dev/bpmp-host-net-vm";
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

            driver_path=/sys/bus/platform/drivers/tegra-mgbe
            if [ ! -d "$driver_path" ]; then
              echo "MGBE0 driver path is missing: $driver_path" >&2
              exit 1
            fi

            found=0
            for device in "$driver_path"/*; do
              [ -d "$device/net" ] || continue
              for path in "$device/net"/*; do
                [ -e "$path" ] || continue
                found=1
                interface="''${path##*/}"
                echo "Quiescing MGBE0 interface $interface from ''${device##*/}"
                ${pkgs.iproute2}/bin/ip link set dev "$interface" down
              done
            done

            if [ "$found" -eq 0 ]; then
              echo "No MGBE0 network interface found under $driver_path" >&2
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
          microvm = {
            qemu.extraArgs = lib.mkIf (config.microvm.hypervisor == "qemu") [
              "-device"
              # Keep the proven, bounded QEMU workaround. Crosvm does not get
              # startup rearm without trace evidence of the same IRQ wedge.
              "vfio-platform,host=${mgbe0.sysfsName},startup-rearm=on"
            ];
            devices = lib.mkIf (config.microvm.hypervisor == "crosvm") [
              {
                bus = "platform";
                path = mgbe0.sysfsName;
                crosvm.dtSymbol = mgbe0.dtSymbol;
              }
            ];
            crosvm = lib.mkIf (config.microvm.hypervisor == "crosvm") {
              deviceTreeOverlays = [ "/run/mgbe0-net-vm.dtbo" ];
              extraArgs = [
                "--nvidia-bpmp-host"
                "/dev/bpmp-host-net-vm"
              ];
            };
          };

          # Crosvm removes VFIO mappings as soon as the guest exits. Keep a
          # normal shutdown hook, and expose a GIVC service which powers off
          # only after the driver's ndo_stop path succeeds. A quiesce failure
          # therefore leaves the guest running and becomes a loud host timeout
          # instead of silently tearing down live DMA.
          systemd.services.quiesce-mgbe0 = lib.mkIf (config.microvm.hypervisor == "crosvm") {
            description = "Quiesce MGBE0 before Crosvm shutdown";
            wantedBy = [ "multi-user.target" ];
            after = [
              "givc-net-vm.service"
              "NetworkManager.service"
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
              ExecStop = quiesceMgbe0;
            };
          };

          systemd.services.ghaf-mgbe0-poweroff = lib.mkIf (config.microvm.hypervisor == "crosvm") {
            description = "Quiesce MGBE0 and power off net-vm";
            after = [
              "givc-net-vm.service"
              "NetworkManager.service"
              "quiesce-mgbe0.service"
            ];
            serviceConfig.Type = "oneshot";
            script = ''
              set -euo pipefail
              ${pkgs.systemd}/bin/systemctl stop quiesce-mgbe0.service
              ${pkgs.systemd}/bin/systemctl start --no-block poweroff.target
            '';
          };

          givc.sysvm.capabilities.services = lib.optionals (config.microvm.hypervisor == "crosvm") [
            "ghaf-mgbe0-poweroff.service"
          ];
        }
      )
    ];
  };
}
