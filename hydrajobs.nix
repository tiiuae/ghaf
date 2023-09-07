# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
}: {
  hydraJobs = let
    disableDemoAppsModule = {
      ghaf.graphics.weston.enableDemoApplications = lib.mkForce false;
    };
  in {
    generic-x86_64-debug.x86_64-linux = self.packages.x86_64-linux.generic-x86_64-debug;
    lenovo-x1-carbon-gen11-debug.x86_64-linux = self.packages.x86_64-linux.lenovo-x1-carbon-gen11-debug;
    nvidia-jetson-orin-agx-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-agx-debug;
    nvidia-jetson-orin-nx-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-nx-debug;
    intel-vm-debug.x86_64-linux = self.packages.x86_64-linux.vm-debug;
    imx8qm-mek-debug.aarch64-linux = self.packages.aarch64-linux.imx8qm-mek-debug;
    docs.x86_64-linux = self.packages.x86_64-linux.doc;
    docs.aarch64-linux = self.packages.aarch64-linux.doc;
    microchip-icicle-kit-debug.x86_64-linux = self.packages.riscv64-linux.microchip-icicle-kit-debug;

    # Build these toplevel derivations to cache cross-compiled packages
    nvidia-jetson-orin-agx-debug-from-x86_64-toplevel.x86_64-linux = self.nixosConfigurations.nvidia-jetson-orin-agx-debug-from-x86_64.config.system.build.toplevel;
    nvidia-jetson-orin-nx-debug-from-x86_64-toplevel.x86_64-linux = self.nixosConfigurations.nvidia-jetson-orin-nx-debug-from-x86_64.config.system.build.toplevel;

    # Build also cross-compiled toplevel derivations without demo apps
    nvidia-jetson-orin-agx-debug-from-x86_64-nodemoapps-toplevel.x86_64-linux =
      (self.nixosConfigurations.nvidia-jetson-orin-agx-debug-from-x86_64.extendModules {
        modules = [disableDemoAppsModule];
      })
      .config
      .system
      .build
      .toplevel;
    nvidia-jetson-orin-nx-debug-from-x86_64-nodemoapps-toplevel.x86_64-linux =
      (self.nixosConfigurations.nvidia-jetson-orin-nx-debug-from-x86_64.extendModules {
        modules = [disableDemoAppsModule];
      })
      .config
      .system
      .build
      .toplevel;
  };
}
