# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Focused evaluation checks for accelerated Orin Crosvm targets.
{
  self,
  lib,
  runCommand,
}:
let
  agx = self.nixosConfigurations."nvidia-jetson-orin-agx-accelerated-guivm-debug".config;
  nxConfiguration = self.nixosConfigurations."nvidia-jetson-orin-nx-accelerated-guivm-debug";
  nx = nxConfiguration.config;
  standardNx = self.nixosConfigurations."nvidia-jetson-orin-nx-debug".config;
  nxQemuFallback =
    (nxConfiguration.extendModules {
      modules = [
        {
          ghaf.virtualization.vmConfig.sysvms.netvm.vmm = lib.mkForce "qemu";
        }
      ];
    }).config;

  vmConfig = host: name: lib.ghaf.vm.getConfig host.microvm.vms.${name};
  managedVmNames = [
    "admin-vm"
    "chromium-vm"
    "flatpak-vm"
    "gui-vm"
    "net-vm"
  ];
  managedVmsUse = host: vmm: lib.all (vm: vm.type == vmm) host.ghaf.hardware.passthrough.vhotplug.vms;
  hasShare = tag: vm: lib.any (share: share.tag == tag) vm.microvm.shares;
  hasArgPair =
    flag: value: args:
    if builtins.length args < 2 then
      false
    else
      (builtins.head args == flag && builtins.elemAt args 1 == value)
      || hasArgPair flag value (builtins.tail args);

  nxNet = vmConfig nx "net-vm";
  nxGui = vmConfig nx "gui-vm";
  fallbackNet = vmConfig nxQemuFallback "net-vm";
  expectedGuiDevices = [
    "60000000.vm_hs_p"
    "80000000.vm_cma_p"
    "b0000000.scanout_p"
    "13830000.disp_caps_pt"
    "13870000.disp_chan_pt"
    "138c8000.disp_cursor_pt"
    "17000000.gpu"
    "13e00000.host1x_pt"
    "15340000.vic"
    "15480000.nvdec"
    "15540000.nvjpg"
  ];

  assertions = [
    {
      name = "accelerated AGX defaults every managed VM to Crosvm";
      ok =
        managedVmsUse agx "crosvm"
        && map (vm: vm.name) agx.ghaf.hardware.passthrough.vhotplug.vms == managedVmNames;
    }
    {
      name = "accelerated NX defaults every managed VM to Crosvm";
      ok =
        managedVmsUse nx "crosvm"
        && map (vm: vm.name) nx.ghaf.hardware.passthrough.vhotplug.vms == managedVmNames;
    }
    {
      name = "accelerated Orin targets select ghaf-device-manager";
      ok =
        agx.ghaf.hardware.passthrough.deviceManager.backend == "ghaf-device-manager"
        && nx.ghaf.hardware.passthrough.deviceManager.backend == "ghaf-device-manager"
        && agx.systemd.services."ghaf-device-manager".enable
        && nx.systemd.services."ghaf-device-manager".enable
        && !(agx.systemd.services.vhotplug.enable or false)
        && !(nx.systemd.services.vhotplug.enable or false);
    }
    {
      name = "standard NX keeps its QEMU and vhotplug defaults";
      ok =
        standardNx.ghaf.virtualization.vmConfig.defaultSysVmVmm == "qemu"
        && standardNx.ghaf.virtualization.vmConfig.defaultAppVmVmm == "qemu"
        && standardNx.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug";
    }
    {
      name = "NX maps its nonzero-domain PCI Ethernet endpoint for Crosvm";
      ok =
        lib.any (
          device:
          device.bus == "pci"
          && device.path == "0008:01:00.0"
          && device.crosvm.guestAddress == "00:1f.0"
          && device.crosvm.iommu == "off"
        ) nxNet.microvm.devices
        && !nx.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable
        && agx.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable;
    }
    {
      name = "NX Crosvm NetVM reads hwinfo through virtiofs without QEMU arguments";
      ok =
        nxNet.ghaf.services.hwinfo-guest.filePath == "/run/ghaf-hwinfo/hwinfo.json"
        && hasShare "ghaf-hwinfo" nxNet
        && nxNet.microvm.qemu.extraArgs == [ ];
    }
    {
      name = "NX Crosvm GUIVM uses the complete Orin platform layout";
      ok =
        map (device: device.path) nxGui.microvm.devices == expectedGuiDevices
        && nxGui.microvm.crosvm.memoryBase == lib.fromHexString "0x2000000000"
        &&
          nxGui.microvm.crosvm.platformMmio == {
            base = lib.fromHexString "0x60000000";
            size = lib.fromHexString "0x1fa0000000";
          };
    }
    {
      name = "explicit NX QEMU fallback restores vhotplug and fw_cfg";
      ok =
        fallbackNet.microvm.hypervisor == "qemu"
        && nxQemuFallback.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug"
        && nxQemuFallback.systemd.services.vhotplug.enable
        && !(nxQemuFallback.systemd.services."ghaf-device-manager".enable or false)
        && !hasShare "ghaf-hwinfo" fallbackNet
        &&
          hasArgPair "-fw_cfg" "name=opt/com.ghaf.hwinfo,file=/var/lib/ghaf-hwinfo/hwinfo.json"
            fallbackNet.microvm.qemu.extraArgs;
    }
  ];
  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (
  failed == [ ]
) "Orin Crosvm target checks failed: ${lib.concatStringsSep "; " failed}";
runCommand "orin-crosvm-targets" { } ''touch "$out"''
