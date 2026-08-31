# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm;
  support = pkgs.nvidia-jetpack.orinVirtualizationSupport;
  mgbe0 = support.passthrough.mgbe0;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable =
    lib.mkEnableOption "MGBE0 passthrough to Net VM on NVIDIA Orin";

  config = lib.mkIf cfg.enable {
    hardware.nvidia-jetpack.virtualization = {
      bpmpHost.consumers.net-vm = support.bpmpPolicies.mgbe0.proxy;
      mgbe0Host.enable = true;
    };

    systemd.services."microvm@net-vm" = {
      requires = [ "bindMgbe0.service" ];
      after = [ "bindMgbe0.service" ];
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
          hardware.nvidia-jetpack.virtualization.mgbe0Guest.enable = true;
          ghaf.virtualization.qemu.package = lib.mkForce pkgs.ghaf-nvidia-qemu-bpmp;
          microvm.qemu.extraArgs = [
            "-device"
            "vfio-platform,host=${mgbe0.sysfsName},startup-rearm=on"
          ];
        }
      )
    ];
  };
}
