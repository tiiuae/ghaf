# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  runCommand,
}:
let
  orinTargets = lib.filterAttrs (
    name: _: lib.hasPrefix "nvidia-jetson-orin-" name
  ) self.nixosConfigurations;
  hostConfig = target: target.config;
  vmConfigs = host: map (vm: vm.evaluatedConfig.config) (builtins.attrValues host.microvm.vms);
  usesCrosvm = host: lib.all (vm: vm.microvm.hypervisor == "crosvm") (vmConfigs host);

  targetAssertions = lib.mapAttrsToList (
    name: target:
    let
      host = hostConfig target;
    in
    {
      inherit name;
      ok =
        host.ghaf.hardware.nvidia.orin.crosvm.enable
        && host.ghaf.virtualization.vmConfig.defaultSysVmVmm == "crosvm"
        && host.ghaf.virtualization.vmConfig.defaultAppVmVmm == "crosvm"
        && host.ghaf.hardware.passthrough.deviceManager.backend == "ghaf-device-manager"
        && usesCrosvm host
        && host.systemd.services ? ghaf-device-manager
        && !(host.systemd.services ? vhotplug);
    }
  ) orinTargets;

  agx = hostConfig orinTargets.nvidia-jetson-orin-agx-release-from-x86_64;
  agxNetVm = agx.microvm.vms."net-vm".evaluatedConfig.config;
  agxNetService = agx.systemd.services."microvm@net-vm";
  qemuFallback =
    (orinTargets.nvidia-jetson-orin-agx-release-from-x86_64.extendModules {
      modules = [
        {
          ghaf.virtualization.vmConfig = {
            defaultSysVmVmm = lib.mkForce "qemu";
            defaultAppVmVmm = lib.mkForce "qemu";
          };
        }
      ];
    }).config;

  assertions = targetAssertions ++ [
    {
      name = "all exported Orin configurations are covered";
      ok = builtins.length targetAssertions == 104;
    }
    {
      name = "AGX NetVM waits for MGBE bind and Crosvm overlay preparation";
      ok = lib.all (unit: lib.elem unit agxNetService.requires) [
        "bindMgbe0.service"
        "prepareMgbe0CrosvmOverlay.service"
        "ghaf-device-manager.service"
      ];
    }
    {
      name = "AGX NetVM consumes the Jetpack-owned Crosvm MGBE overlay";
      ok = agxNetVm.microvm.crosvm.deviceTreeOverlays == [ "/run/mgbe0-net-vm.dtbo" ];
    }
    {
      name = "AGX NetVM consumes host hardware information over virtiofs";
      ok = agxNetVm.ghaf.services.hwinfo-guest.filePath == "/run/ghaf-hwinfo/hwinfo.json";
    }
    {
      name = "explicit QEMU overrides retain the supported rollback path";
      ok =
        qemuFallback.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug"
        && lib.all (vm: vm.microvm.hypervisor == "qemu") (vmConfigs qemuFallback)
        && qemuFallback.systemd.services ? vhotplug
        && !(qemuFallback.systemd.services ? ghaf-device-manager);
    }
  ];

  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (
  failed == [ ]
) "Orin Crosvm target policy: ${lib.concatStringsSep "; " failed}";
runCommand "orin-crosvm-targets" { } ''touch "$out"''
