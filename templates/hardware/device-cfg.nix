# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# PC/board peripheral definitions list
{
  deviceName = "";
  networkPciAddr = "";
  networkPciVid = "";
  networkPciPid = "";
  gpuPciAddr = "";
  gpuPciVid = "";
  gpuPciPid = "";
  usbInputVid = "";
  usbInputPid = "";
  vmm-extraArgs = [
    {
      # Extra args to define the specific system VM params to qemu/crosvm
      vm1 = [];
      vm2 = [];
    }
  ];
  udev-extraRules = '''';
  initrd-kernelModules = [""];
  boot-kernelParams = [""];
}
