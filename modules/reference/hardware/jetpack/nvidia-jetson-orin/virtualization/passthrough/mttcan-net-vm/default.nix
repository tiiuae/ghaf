# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Pass both Orin MTTCAN controllers to net-vm. The host assigns their MMIO and
# IRQ resources with vfio-platform while a dedicated BPMP proxy provides only
# the clocks and resets required by the two controllers.
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
  configuredNetVmVmm = config.ghaf.virtualization.vmConfig.sysvms.netvm.vmm or null;
  isCrosvm =
    (
      if configuredNetVmVmm == null then
        config.ghaf.virtualization.vmConfig.defaultSysVmVmm
      else
        configuredNetVmVmm
    ) == "crosvm";
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

  config = lib.mkIf (cfg.enable && isCrosvm) {
    hardware.nvidia-jetpack.virtualization = {
      bpmpHost.consumers.net-vm = virt-support.bpmpPolicies.mttcan.proxy;
      mttcanHost.enable = true;
    };

    systemd.services."microvm@net-vm" = {
      requires = [ "bindMttcan.service" ];
      after = [ "bindMttcan.service" ];
      environment.GHAF_BPMP_HOST = "/dev/bpmp-host-net-vm";
    };

    ghaf.hardware.definition.netvm.extraModules = [
      (
        {
          inputs,
          pkgs,
          ...
        }:
        {
          imports = [ inputs.jetpack-nixos.nixosModules.orin-virtualization ];
          hardware.nvidia-jetpack.virtualization.mttcanGuest.enable = true;
          environment.systemPackages = [ pkgs.can-utils ];

          microvm = {
            devices = map (controller: {
              bus = "platform";
              path = controller.sysfsName;
              crosvm = {
                inherit (controller) dtSymbol;
                iommu = "off";
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
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
              ExecStop = lib.getExe virt-support.quiesceMttcan;
            };
          };
        }
      )
    ];
  };
}
