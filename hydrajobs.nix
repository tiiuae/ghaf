# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
}: {
  hydraJobs = {
    generic-x86_64-debug.x86_64-linux = self.packages.x86_64-linux.generic-x86_64-debug;
    lenovo-x1-carbon-gen11-debug.x86_64-linux = self.packages.x86_64-linux.lenovo-x1-carbon-gen11-debug;
    nvidia-jetson-orin-agx-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-agx-debug;
    nvidia-jetson-orin-nx-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-nx-debug;
    intel-vm-debug.x86_64-linux = self.packages.x86_64-linux.vm-debug;
    imx8qm-mek-debug.aarch64-linux = self.packages.aarch64-linux.imx8qm-mek-debug;
    docs.x86_64-linux = self.packages.x86_64-linux.doc;
    docs.aarch64-linux = self.packages.aarch64-linux.doc;
    microchip-icicle-kit-debug.x86_64-linux = self.packages.riscv64-linux.microchip-icicle-kit-debug;

    # Build cross-copmiled images
    nvidia-jetson-orin-agx-debug-from-x86_64.x86_64-linux = self.packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64;
    nvidia-jetson-orin-nx-debug-from-x86_64.x86_64-linux = self.packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64;

    # Build also cross-compiled images without demo apps
    nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64.x86_64-linux = self.packages.x86_64-linux.nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64;
    nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64.x86_64-linux = self.packages.x86_64-linux.nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64;
  };
}
