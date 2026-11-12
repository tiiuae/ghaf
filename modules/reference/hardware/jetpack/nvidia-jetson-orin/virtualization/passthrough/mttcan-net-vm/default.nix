# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# CAN intentionally belongs to net-vm in these reference images, alongside
# external networking. A compromised NetVM can therefore drive both CAN buses.
# The host assigns MMIO and IRQ resources with vfio-platform and restricts
# BPMP clock/reset access to the resources required by the controllers.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.mttcan_net_vm;
  virt-support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  mttcan = virt-support.passthrough.mttcan;
  mgbe0Enabled = config.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable;
  isCrosvm =
    lib.ghaf.vm.resolveSysVmVmm {
      inherit config;
      vmName = "netvm";
    } == "crosvm";
  mttcanOverlay = virt-support.mkMttcanOverlay {
    inherit pkgs;
    support = virt-support;
    hostDtb = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
  };
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.mttcan_net_vm.enable =
    lib.mkEnableOption "both Orin MTTCAN controllers in the NetVM";

  config = lib.mkMerge [
    {
      warnings = lib.optional (
        cfg.enable && !isCrosvm
      ) "Orin MTTCAN passthrough requires Crosvm; CAN is unavailable with the selected NetVM hypervisor.";
    }
    (lib.mkIf (cfg.enable && isCrosvm) {
      hardware.nvidia-jetpack.virtualization = {
        bpmpHost.consumers.net-vm = virt-support.bpmpPolicies.mttcan.proxy;
        mttcanHost.enable = true;
      };

      systemd.services."microvm@net-vm" = {
        requires = [ "bindMttcan.service" ];
        after = [ "bindMttcan.service" ];
        environment.GHAF_BPMP_HOST = "/dev/bpmp-host-net-vm";
        serviceConfig.ExecStartPre = [
          "${pkgs.systemd}/bin/udevadm wait --initialized=yes --timeout=30 /dev/bpmp-host-net-vm"
        ];
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
            hardware.nvidia-jetpack.virtualization.mttcanGuest.enable = true;
            environment.systemPackages = lib.optionals config.ghaf.profiles.debug.enable [ pkgs.can-utils ];

            microvm = {
              devices = map (controller: {
                bus = "platform";
                path = controller.sysfsName;
                crosvm = {
                  inherit (controller) dtSymbol;
                };
              }) mttcan.controllers;

              crosvm = {
                deviceTreeOverlays = [ "${mttcanOverlay}" ];
                extraArgs = lib.optionals (!mgbe0Enabled) [
                  "--nvidia-bpmp-host"
                  "/dev/bpmp-host-net-vm"
                ];
              };
            };

            systemd.services.quiesce-mttcan = {
              description = "Quiesce both MTTCAN interfaces before Crosvm shutdown";
              wantedBy = [ "multi-user.target" ];
              after = [
                "givc-net-vm.service"
                "NetworkManager.service"
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.coreutils}/bin/true";
                # CAN is DMA-less; failed quiescing must not block guest shutdown.
                ExecStop = "-${lib.getExe virt-support.quiesceMttcan}";
              };
            };
          }
        )
      ];
    })
  ];
}
