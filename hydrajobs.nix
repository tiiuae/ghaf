# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{self}: {
  hydraJobs = {
    generic-x86_64-debug.x86_64-linux = self.packages.x86_64-linux.generic-x86_64-debug;
    nvidia-jetson-orin-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-debug;
    intel-vm-debug.x86_64-linux = self.packages.x86_64-linux.vm-debug;
  };
}
