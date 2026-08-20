# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-free check for TPM parity between encrypted QEMU and Crosvm system VMs.
{
  self,
  lib,
  runCommand,
}:
let
  qemuHost = self.nixosConfigurations.lenovo-t14-amd-gen5-release.config;
  crosvmHost = self.nixosConfigurations.intel-laptop-release.config;

  # This map is the pinned cross-VMM storage contract. The authoritative NV
  # indices remain in the corresponding {admin,audio,gui,net}vm-base modules;
  # changing one side without the other must fail this parity check.
  systemVms = {
    "admin-vm" = "0x81701000";
    "audio-vm" = "0x81702000";
    "gui-vm" = "0x81703000";
    "net-vm" = "0x81704000";
  };
  appVms = [
    "business-vm"
    "chrome-vm"
    "comms-vm"
    "flatpak-vm"
    "media-vm"
  ];

  vmConfig = host: name: host.microvm.vms.${name}.evaluatedConfig.config;

  hasArgPair =
    flag: value: args:
    if builtins.length args < 2 then
      false
    else
      (builtins.head args == flag && builtins.elemAt args 1 == value)
      || hasArgPair flag value (builtins.tail args);

  patchNames = vm: map (patch: patch.name) vm.boot.kernelPatches;
  waitsForTpm =
    vm:
    lib.elem "dev-tpmrm0.device" vm.systemd.services.storagevm-enroll.requires
    && lib.elem "dev-tpmrm0.device" vm.systemd.services.storagevm-enroll.after;
  formatsAfterPersistExpansion =
    host: name:
    let
      service = host.systemd.services."format-microvm-storage-${name}";
    in
    lib.elem "extendbtrfs.service" service.after && lib.elem "extendbtrfs.service" service.requires;

  systemVmAssertions = lib.concatLists (
    lib.mapAttrsToList (
      name: rootNVIndex:
      let
        qemu = vmConfig qemuHost name;
        crosvm = vmConfig crosvmHost name;
      in
      [
        {
          name = "${name}: QEMU release VM enables TPM passthrough";
          ok = qemu.microvm.hypervisor == "qemu" && qemu.ghaf.virtualization.microvm.tpm.passthrough.enable;
        }
        {
          name = "${name}: QEMU release VM uses the expected TPM resource-manager device";
          ok =
            hasArgPair "-tpmdev" "passthrough,id=tpmrm0,path=/dev/tpmrm0,cancel-path=/tmp/cancel"
              qemu.microvm.qemu.extraArgs;
        }
        {
          name = "${name}: Crosvm release VM enables TPM passthrough";
          ok =
            crosvm.microvm.hypervisor == "crosvm" && crosvm.ghaf.virtualization.microvm.tpm.passthrough.enable;
        }
        {
          name = "${name}: Crosvm release VM uses the same TPM resource-manager device";
          ok = hasArgPair "--tpm-device" "/dev/tpmrm0" crosvm.microvm.crosvm.extraArgs;
        }
        {
          name = "${name}: both VMMs preserve the VM-specific TPM NV index";
          ok =
            qemu.ghaf.virtualization.microvm.tpm.passthrough.rootNVIndex == rootNVIndex
            && crosvm.ghaf.virtualization.microvm.tpm.passthrough.rootNVIndex == rootNVIndex;
        }
        {
          name = "${name}: both release VMs enable encrypted persistent storage";
          ok = qemu.ghaf.storagevm.encryption.enable && crosvm.ghaf.storagevm.encryption.enable;
        }
        {
          name = "${name}: both release VMs wait for the TPM before storage enrollment";
          ok = waitsForTpm qemu && waitsForTpm crosvm;
        }
        {
          name = "${name}: encrypted release storage waits for persistent filesystem expansion";
          ok = formatsAfterPersistExpansion qemuHost name && formatsAfterPersistExpansion crosvmHost name;
        }
        {
          name = "${name}: Crosvm guest includes the virtio TPM transport";
          ok = lib.elem "chromiumos-virtio-tpm" (patchNames crosvm);
        }
        {
          name = "${name}: Crosvm release initrd loads the virtio TPM transport";
          ok = lib.elem "tpm_virtio" crosvm.boot.initrd.kernelModules;
        }
      ]
    ) systemVms
  );

  appVmAssertions = map (
    name:
    let
      vm = vmConfig crosvmHost name;
    in
    {
      name = "${name}: Crosvm AppVM retains its isolated swtpm backend";
      ok =
        vm.microvm.hypervisor == "crosvm"
        && vm.ghaf.virtualization.microvm.tpm.emulated.enable
        && vm.ghaf.virtualization.microvm.tpm.emulated.runInVM
        && lib.elem "tpm_virtio" vm.boot.initrd.kernelModules
        && hasArgPair "--swtpm" "vtpm.sock" vm.microvm.crosvm.extraArgs;
    }
  ) appVms;

  assertions = [
    {
      name = "QEMU host grants the microvm user TPM device access";
      ok = lib.elem "tss" qemuHost.users.users.microvm.extraGroups;
    }
    {
      name = "Crosvm host grants the microvm user TPM device access";
      ok = lib.elem "tss" crosvmHost.users.users.microvm.extraGroups;
    }
  ]
  ++ systemVmAssertions
  ++ appVmAssertions;

  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (failed == [ ]) "microvm TPM VMM parity: ${lib.concatStringsSep "; " failed}";
runCommand "microvm-tpm-vmm-parity" { } ''touch "$out"''
