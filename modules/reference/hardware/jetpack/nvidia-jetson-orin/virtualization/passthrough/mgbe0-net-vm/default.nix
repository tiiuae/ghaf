# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass the AGX Orin's on-SoC ethernet (MGBE0, ethernet@6800000) to net-vm.
#
#   data     vfio-platform hands the MAC's MMIO + IRQs to the guest; MGBE0 is
#            alone in its IOMMU group, so VFIO takes it cleanly.
#   control  the guest BPMP transport forwards requests to net-vm's dedicated
#            BPMP host proxy from jetpack-nixos. QEMU emits its guest DT while
#            Crosvm consumes Jetpack's live-DT-derived overlay.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm;
  virt-support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  configuredNetVmVmm = config.ghaf.virtualization.vmConfig.sysvms.netvm.vmm or null;
  isCrosvm =
    (
      if configuredNetVmVmm == null then
        config.ghaf.virtualization.vmConfig.defaultSysVmVmm
      else
        configuredNetVmVmm
    ) == "crosvm";
  mgbe0 = virt-support.passthrough.mgbe0;
  hostServices = [
    "bindMgbe0.service"
  ]
  ++ lib.optionals isCrosvm [ "prepareMgbe0CrosvmOverlay.service" ];
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable =
    lib.mkEnableOption "MGBE0 (${mgbe0.nodeName}) passthrough to the Net-VM on NVIDIA Orin";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !isCrosvm || config.ghaf.givc.enable;
        message = "Crosvm MGBE0 passthrough requires GIVC for coordinated DMA quiescing.";
      }
    ];
    hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm =
      virt-support.bpmpPolicies.mgbe0.proxy;
    hardware.nvidia-jetpack.virtualization.mgbe0Host.enable = true;
    systemd.services."microvm@net-vm" = {
      requires = hostServices;
      after = hostServices;
      environment.GHAF_BPMP_HOST = "/dev/bpmp-host-net-vm";
    };

    ghaf.hardware.definition.netvm.extraModules = [
      (
        {
          config,
          inputs,
          pkgs,
          ...
        }:
        {
          imports = [ inputs.jetpack-nixos.nixosModules.orin-virtualization ];
          hardware.nvidia-jetpack.virtualization.mgbe0Guest.enable = true;

          # Only this VM gets the QEMU that has the BPMP bridge and, crucially,
          # still has -device vfio-platform (removed upstream in 10.2). It also
          # emits MGBE0's guest DT node.
          ghaf.virtualization.qemu.package = lib.mkIf (config.microvm.hypervisor == "qemu") (
            lib.mkForce pkgs.ghaf-nvidia-qemu-bpmp
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
              deviceTreeOverlays = [ mgbe0.crosvmOverlayPath ];
              extraArgs = [
                "--nvidia-bpmp-host"
                "/dev/bpmp-host-net-vm"
              ];
            };
          };

          # Keep the DMA owner alive if quiescing fails; an abrupt stop removes its mappings.
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
              ExecStop = lib.getExe virt-support.quiesceMgbe0;
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
              # Run on every request; stopping an already failed unit can report success.
              if ! ${lib.getExe virt-support.quiesceMgbe0}; then
                echo "ERROR: MGBE0 quiesce failed; retaining net-vm and its DMA mappings" >&2
                exit 1
              fi
              # GIVC retries must not replace an in-progress shutdown transaction.
              ${pkgs.systemd}/bin/systemctl start --no-block --job-mode=replace-irreversibly poweroff.target
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
