# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  runCommand,
}:
let
  config = name: self.nixosConfigurations.${name}.config;
  agx = config "nvidia-jetson-orin-agx-accelerated-guivm-debug";
  nx = config "nvidia-jetson-orin-nx-accelerated-guivm-debug";
  splitAgx = config "nvidia-jetson-orin-agx-debug";
  splitNx = config "nvidia-jetson-orin-nx-debug";
  releaseAgx = config "nvidia-jetson-orin-agx-release";
  nxQemu =
    (self.nixosConfigurations."nvidia-jetson-orin-nx-accelerated-guivm-debug".extendModules {
      modules = [
        { ghaf.virtualization.vmConfig.sysvms.guivm.vmm = lib.mkForce "qemu"; }
      ];
    }).config;

  vm = host: name: lib.ghaf.vm.getConfig host.microvm.vms.${name};
  uses = host: vmm: lib.all (entry: entry.type == vmm) host.ghaf.hardware.passthrough.vhotplug.vms;
  hasArg = needle: guest: lib.any (lib.hasInfix needle) guest.microvm.crosvm.extraArgs;
  bpmpConsumers = host: host.ghaf.hardware.nvidia.virtualization.host.bpmp.consumers;
  hasReceiverDeny =
    host:
    lib.any (
      rule: lib.any (device: device.vendorId == "046d" && device.productId == "c52b") rule.deny
    ) host.ghaf.hardware.passthrough.usb.guivmRules;
  hasShutdown =
    host: name:
    host.systemd.services ? "ghaf-crosvm-shutdown-${name}"
    && host.systemd.services."microvm@${name}".serviceConfig.TimeoutStopSec == "35";

  agxGui = vm agx "gui-vm";
  nxGui = vm nx "gui-vm";
  splitAgxGpu = vm splitAgx "gpu-vm";
  splitAgxDisp = vm splitAgx "disp-vm";
  splitNxNet = vm splitNx "net-vm";
  nxQemuGui = vm nxQemu "gui-vm";
  nxApp = vm nx "chromium-vm";
  memoryBase = lib.fromHexString "0x2000000000";
  managedNames = host: map (entry: entry.name) host.ghaf.hardware.passthrough.vhotplug.vms;
  assertions = [
    {
      name = "all four debug targets select Crosvm and ghaf-device-manager";
      ok =
        lib.all
          (
            host:
            uses host "crosvm"
            && host.ghaf.hardware.passthrough.deviceManager.backend == "ghaf-device-manager"
            && host.systemd.services."ghaf-device-manager".enable
            && !(host.systemd.services.vhotplug.enable or false)
          )
          [
            agx
            nx
            splitAgx
            splitNx
          ];
    }
    {
      name = "release targets retain QEMU defaults";
      ok =
        releaseAgx.ghaf.virtualization.vmConfig.defaultSysVmVmm == "qemu"
        && releaseAgx.ghaf.virtualization.vmConfig.defaultAppVmVmm == "qemu";
    }
    {
      name = "GPU, display, and combined guests receive only their payload arguments";
      ok =
        splitAgxGpu.microvm.crosvm.memoryBase == memoryBase
        && splitAgxDisp.microvm.crosvm.memoryBase == memoryBase
        && nxGui.microvm.crosvm.memoryBase == memoryBase
        && hasArg "17000000.gpu" splitAgxGpu
        && !(hasArg "13830000.disp_caps_pt" splitAgxGpu)
        && hasArg "13830000.disp_caps_pt" splitAgxDisp
        && !(hasArg "17000000.gpu" splitAgxDisp)
        && hasArg "17000000.gpu" nxGui
        && hasArg "13830000.disp_caps_pt" nxGui;
    }
    {
      name = "BPMP policies and device paths are isolated per VM";
      ok =
        builtins.attrNames (bpmpConsumers splitAgx) == [
          "disp-vm"
          "gpu-vm"
          "net-vm"
        ]
        && builtins.attrNames (bpmpConsumers nx) == [ "gui-vm" ]
        && hasArg "/dev/bpmp-host-gpu-vm" splitAgxGpu
        && hasArg "/dev/bpmp-host-disp-vm" splitAgxDisp
        && hasArg "/dev/bpmp-host-gui-vm" agxGui
        && agx.systemd.services."microvm@gui-vm".environment.GHAF_BPMP_HOST == "/dev/bpmp-host-gui-vm";
    }
    {
      name = "NX PCI Ethernet uses the Crosvm-specific guest address";
      ok =
        lib.any (device: device.bus == "pci" && device.path == "0008:01:00.0") splitNxNet.microvm.devices
        &&
          splitNxNet.microvm.crosvm.pciDeviceOptions."0008:01:00.0" == {
            guestAddress = "00:1f.0";
            iommu = "off";
            dtSymbol = null;
          };
    }
    {
      name = "bounded guest-owned shutdown covers system and application VMs";
      ok =
        lib.all (hasShutdown nx) (managedNames nx)
        && agxGui.systemd.services ? ghaf-crosvm-poweroff
        && splitAgxGpu.systemd.services ? givc-gpu-vm
        && splitAgxDisp.systemd.services ? givc-disp-vm
        && lib.elem "ghaf-crosvm-poweroff.service" agxGui.givc.sysvm.capabilities.services
        && nxApp.systemd.user.services ? ghaf-crosvm-poweroff
        && lib.elem "ghaf-crosvm-poweroff.service" nxApp.ghaf.givc.appvm.services;
    }
    {
      name = "MGBE and DCE shutdown hooks are present";
      ok =
        (vm agx "net-vm").systemd.services ? ghaf-mgbe0-poweroff
        && agxGui.systemd.services ? dce-rm-deinit
        && splitAgxDisp.systemd.services ? dce-rm-deinit;
    }
    {
      name = "QEMU GUI fallback restores vhotplug and receiver denial";
      ok =
        nxQemuGui.microvm.hypervisor == "qemu"
        && nxQemu.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug"
        && nxQemu.systemd.services.vhotplug.enable
        && hasReceiverDeny nxQemu
        && !hasReceiverDeny nx;
    }
  ];
  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (
  failed == [ ]
) "Orin Crosvm target checks failed: ${lib.concatStringsSep "; " failed}";
runCommand "orin-crosvm-targets" { } ''touch "$out"''
