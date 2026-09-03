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
  # Nodemoapps, LUKS, UKI, and cross variants only extend these base targets.
  # Check the bases here; the eval and build matrices exercise every variant.
  baseTargetNames = [
    "nvidia-jetson-orin-agx-debug"
    "nvidia-jetson-orin-agx-release"
    "nvidia-jetson-orin-agx-industrial-debug"
    "nvidia-jetson-orin-agx-industrial-release"
    "nvidia-jetson-orin-agx-verity-debug"
    "nvidia-jetson-orin-agx-verity-release"
    "nvidia-jetson-orin-agx64-debug"
    "nvidia-jetson-orin-agx64-release"
    "nvidia-jetson-orin-nx-debug"
    "nvidia-jetson-orin-nx-release"
  ];
  baseTargets = lib.getAttrs baseTargetNames orinTargets;
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
        && host.ghaf.hardware.nvidia.passthroughs.gui_vm.enable
        && host.ghaf.hardware.nvidia.passthroughs.mttcan_net_vm.enable
        && host.hardware.nvidia-jetpack.virtualization.mttcanHost.enable
        && host.ghaf.virtualization.microvm.guivm.enable
        && !host.ghaf.profiles.graphics.enable
        && !host.ghaf.graphics.cosmic.enable
        &&
          host.hardware.nvidia-jetpack.virtualization.gpuPassthroughHost.assignments == {
            gui-vm.role = "combined";
          }
        && host.microvm.vms ? "gui-vm"
        && usesCrosvm host
        && host.systemd.services ? ghaf-device-manager
        && !(host.systemd.services ? vhotplug);
    }
  ) baseTargets;

  agx = hostConfig baseTargets.nvidia-jetson-orin-agx-release;
  agxNetVm = agx.microvm.vms."net-vm".evaluatedConfig.config;
  agxNetService = agx.systemd.services."microvm@net-vm";
  nx = hostConfig baseTargets.nvidia-jetson-orin-nx-debug;
  nxNetVm = nx.microvm.vms."net-vm".evaluatedConfig.config;
  nxNetService = nx.systemd.services."microvm@net-vm";
  nxPlatformDevices = lib.filter (device: device.bus == "platform") nxNetVm.microvm.devices;
  nxMttcanDevices = lib.filter (device: lib.hasSuffix ".mttcan" device.path) nxPlatformDevices;
  nxMttcanModulePackages = lib.filter (
    package: (package.pname or "") == "l4t-mttcan-modules"
  ) nxNetVm.boot.extraModulePackages;
  nxGuiShutdown =
    (hostConfig baseTargets.nvidia-jetson-orin-nx-debug).systemd.services."ghaf-crosvm-shutdown-gui-vm";
  nxGuiShutdownScript = nxGuiShutdown.serviceConfig.ExecStop;
  splitAgx =
    (baseTargets.nvidia-jetson-orin-agx-debug.extendModules {
      modules = [
        self.nixosModules.jetpack-orin-gpu-partitioning
        {
          ghaf.hardware.nvidia.passthroughs = {
            gui_vm.enable = lib.mkForce false;
            gpu_vm.enable = true;
            disp_vm.enable = true;
          };
        }
      ];
    }).config;
  splitVmConfigs = map (vm: vm.evaluatedConfig.config) (builtins.attrValues splitAgx.microvm.vms);
  qemuFallback =
    (baseTargets.nvidia-jetson-orin-agx-release.extendModules {
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
      name = "all expected Orin configurations are exported";
      ok = builtins.length (builtins.attrNames orinTargets) == 104;
    }
    {
      name = "AGX NetVM waits for MGBE bind and Crosvm overlay preparation";
      ok = lib.all (unit: lib.elem unit agxNetService.requires) [
        "bindMgbe0.service"
        "prepareMgbe0CrosvmOverlay.service"
        "bindMttcan.service"
        "ghaf-device-manager.service"
      ];
    }
    {
      name = "AGX NetVM consumes the Jetpack-owned MGBE and MTTCAN overlays";
      ok =
        lib.elem "/run/mgbe0-net-vm.dtbo" agxNetVm.microvm.crosvm.deviceTreeOverlays
        && lib.any (
          overlay: lib.hasInfix "mttcan-crosvm-overlay.dtbo" (toString overlay)
        ) agxNetVm.microvm.crosvm.deviceTreeOverlays;
    }
    {
      name = "NX NetVM waits for MTTCAN binding and owns both controllers";
      ok =
        lib.elem "bindMttcan.service" nxNetService.requires
        && lib.length nxMttcanDevices == 2
        && lib.any (
          device: device.path == "c310000.mttcan" && device.crosvm.dtSymbol == "mttcan0"
        ) nxMttcanDevices
        && lib.any (
          device: device.path == "c320000.mttcan" && device.crosvm.dtSymbol == "mttcan1"
        ) nxMttcanDevices
        && lib.all (device: device.crosvm.iommu == "off") nxMttcanDevices
        && lib.all (module: lib.elem module nxNetVm.boot.kernelModules) [
          "nvpps"
          "mttcan"
        ]
        && lib.length nxNetVm.boot.extraModulePackages == 1
        && lib.length nxMttcanModulePackages == 1;
    }
    {
      name = "NX NetVM BPMP policy contains both MTTCAN controllers";
      ok =
        lib.all (id: lib.elem id nx.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm.clocks)
          [
            9
            10
            11
            12
            94
            284
            285
          ]
        &&
          lib.all (id: lib.elem id nx.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers.net-vm.resets)
            [
              4
              5
            ];
    }
    {
      name = "AGX NetVM consumes host hardware information over virtiofs";
      ok = agxNetVm.ghaf.services.hwinfo-guest.filePath == "/run/ghaf-hwinfo/hwinfo.json";
    }
    {
      name = "Crosvm shutdown is bounded and reuses the MicroVM helper";
      ok =
        nxGuiShutdown.serviceConfig.TimeoutStopSec == "95"
        && nxGuiShutdown.serviceConfig.WorkingDirectory == "/var/lib/microvms/gui-vm";
    }
    {
      name = "Ghaf composes the split GPU and display VM target";
      ok =
        !splitAgx.ghaf.virtualization.microvm.guivm.enable
        && splitAgx.ghaf.virtualization.microvm.gpuvm.enable
        && splitAgx.ghaf.virtualization.microvm.dispvm.enable
        &&
          splitAgx.hardware.nvidia-jetpack.virtualization.gpuPassthroughHost.assignments == {
            gpu-vm.role = "compute";
            disp-vm.role = "display";
          }
        && splitAgx.microvm.vms ? "gpu-vm"
        && splitAgx.microvm.vms ? "disp-vm"
        && lib.all (vm: vm.microvm.hypervisor == "crosvm") splitVmConfigs;
    }
    {
      name = "explicit QEMU overrides retain the supported rollback path";
      ok =
        qemuFallback.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug"
        && !qemuFallback.hardware.nvidia-jetpack.virtualization.mttcanHost.enable
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
runCommand "orin-crosvm-targets" { } ''
  grep -Fq 'while ((SECONDS < grace_deadline))' ${nxGuiShutdownScript}
  grep -Fq /booted/bin/microvm-shutdown ${nxGuiShutdownScript}
  touch "$out"
''
