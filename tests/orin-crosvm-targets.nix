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
  pkvmAgx = orinTargets.nvidia-jetson-orin-agx-accelerated-guivm-pkvm-debug.config;
  pkvmNetVm = pkvmAgx.microvm.vms."net-vm".evaluatedConfig.config;
  pkvmGuiVm = pkvmAgx.microvm.vms."gui-vm".evaluatedConfig.config;
  pkvmGuiDevices = lib.filter (device: device.bus == "platform") pkvmGuiVm.microvm.devices;
  pkvmGuestMemory =
    lib.foldl' (total: name: total + pkvmAgx.microvm.vms.${name}.evaluatedConfig.config.microvm.mem) 0
      [
        "admin-vm"
        "net-vm"
        "gui-vm"
      ];
  pkvmWlan = lib.findFirst (
    device: device.bus == "pci" && device.path == "0001:01:00.0"
  ) (throw "protected AGX NetVM WLAN device not found") pkvmNetVm.microvm.devices;

  assertions = targetAssertions ++ [
    {
      name = "all expected Orin configurations are exported";
      # The pKVM debug target adds a native and a cross export to the parent
      # Orin target matrix.
      ok = builtins.length (builtins.attrNames orinTargets) == 106;
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
        && lib.all (vm: vm.microvm.hypervisor == "qemu") (vmConfigs qemuFallback)
        && qemuFallback.systemd.services ? vhotplug
        && !(qemuFallback.systemd.services ? ghaf-device-manager);
    }
    {
      name = "protected AGX NetVM retains the host IOMMU and uses the pKVM PCI backend";
      ok =
        pkvmAgx.ghaf.hardware.nvidia.orin.agx.enableNetvmWlanPCIPassthrough
        && pkvmAgx.ghaf.hardware.nvidia.orin.agx.netvmWlanPCICrosvmIommu == "pkvm-iommu"
        && pkvmWlan.crosvm.iommu == "pkvm-iommu"
        && pkvmWlan.crosvm.guestAddress == "00:1f.0"
        && lib.any (
          overlay: overlay.name == "rtw8822ce-protected-assignment"
        ) pkvmAgx.hardware.deviceTree.overlays
        && !(lib.any (
          overlay: overlay.name == "agx-ethernet-pci-passthough-overlay"
        ) pkvmAgx.hardware.deviceTree.overlays);
    }
    {
      name = "protected AGX GUIVM uses bounded memory and pKVM assignment for every platform resource";
      ok =
        pkvmGuestMemory == 8192
        && builtins.length pkvmGuiDevices == 11
        && lib.all (device: device.crosvm.iommu == "pkvm-iommu") pkvmGuiDevices
        && pkvmGuiVm.microvm.crosvm.protection.mode == "protected-without-firmware"
        && pkvmGuiVm.microvm.crosvm.protection.allowDeviceAssignment
        && pkvmGuiVm.microvm.shares == [ ]
        && !pkvmAgx.ghaf.virtualization.microvm.appvm.enable
        && !(pkvmAgx.microvm.vms ? "chromium-vm")
        && pkvmAgx.microvm.vms."gui-vm".autostart;
    }
    {
      name = "protected AGX GUIVM keeps the Logitech receiver host-mediated";
      ok =
        lib.any (
          rule:
          rule.targetVm == "gui-vm"
          && (rule.includeUsb or false)
          && lib.any (allow: (allow.name or "") == "^Logitech K400 Plus$") rule.allow
        ) pkvmAgx.ghaf.hardware.passthrough.vhotplug.evdevRules
        && lib.any (
          device: device.vendorId == "046d" && device.productId == "c52b"
        ) pkvmAgx.ghaf.hardware.passthrough.usb.guivmDeny;
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
