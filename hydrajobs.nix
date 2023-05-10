# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{self}: {
  hydraJobs = {
    intel-nuc-debug.x86_64-linux = self.packages.x86_64-linux.intel-nuc-debug;
    nvidia-jetson-orin-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-debug;
  };
}
