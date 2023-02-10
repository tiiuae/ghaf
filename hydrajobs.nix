# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{self}: {
  hydraJobs = {
    intel-nuc.x86_64-linux = self.packages.x86_64-linux.intel-nuc;
    nvidia-jetson-orin.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin;
  };
}
