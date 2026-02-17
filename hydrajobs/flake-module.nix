# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self, ... }:
let
  mkBpmpEnabled =
    cfg:
    let
      bpmpEnableModule =
        { lib, ... }:
        {
          ghaf.hardware.nvidia = {
            virtualization.enable = lib.mkForce true;
            virtualization.host.bpmp.enable = lib.mkForce true;
            passthroughs.host.uarta.enable = lib.mkForce true;
          };
        };
      newCfg = cfg.extendModules { modules = [ bpmpEnableModule ]; };
      package = newCfg.config.system.build.image;
    in
    package;
in
{
  flake.hydraJobs = {
    generic-x86_64-debug.x86_64-linux = self.packages.x86_64-linux.generic-x86_64-debug;
    lenovo-x1-carbon-gen11-debug.x86_64-linux = self.packages.x86_64-linux.lenovo-x1-carbon-gen11-debug;
    nvidia-jetson-orin-agx-debug.aarch64-linux =
      self.packages.aarch64-linux.nvidia-jetson-orin-agx-debug;
    nvidia-jetson-orin-agx64-debug.aarch64-linux =
      self.packages.aarch64-linux.nvidia-jetson-orin-agx64-debug;
    nvidia-jetson-orin-nx-debug.aarch64-linux = self.packages.aarch64-linux.nvidia-jetson-orin-nx-debug;
    intel-vm-debug.x86_64-linux = self.packages.x86_64-linux.vm-debug;
    nxp-imx8mp-evk-debug.x86_64-linux = self.packages.aarch64-linux.nxp-imx8mp-evk-debug;
    docs.x86_64-linux = self.packages.x86_64-linux.doc;
    # Build cross-compiled images
    nvidia-jetson-orin-agx-debug-from-x86_64.x86_64-linux =
      self.packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64;
    nvidia-jetson-orin-agx64-debug-from-x86_64.x86_64-linux =
      self.packages.x86_64-linux.nvidia-jetson-orin-agx64-debug-from-x86_64;
    nvidia-jetson-orin-nx-debug-from-x86_64.x86_64-linux =
      self.packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64;
    #microchip-icicle-kit-debug-from-x86_64.x86_64-linux =
    # self.packages.x86_64-linux.microchip-icicle-kit-debug-from-x86_64;

    # Build also cross-compiled images without demo apps
    nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64.x86_64-linux =
      self.packages.x86_64-linux.nvidia-jetson-orin-agx-debug-nodemoapps-from-x86_64;
    nvidia-jetson-orin-agx64-debug-nodemoapps-from-x86_64.x86_64-linux =
      self.packages.x86_64-linux.nvidia-jetson-orin-agx64-debug-nodemoapps-from-x86_64;
    nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64.x86_64-linux =
      self.packages.x86_64-linux.nvidia-jetson-orin-nx-debug-nodemoapps-from-x86_64;

    # BPMP virt enabled versions
    nvidia-jetson-orin-agx-debug-bpmp.aarch64-linux = mkBpmpEnabled self.nixosConfigurations.nvidia-jetson-orin-agx-debug;
    nvidia-jetson-orin-agx64-debug-bpmp.aarch64-linux = mkBpmpEnabled self.nixosConfigurations.nvidia-jetson-orin-agx64-debug;
    nvidia-jetson-orin-nx-debug-bpmp.aarch64-linux = mkBpmpEnabled self.nixosConfigurations.nvidia-jetson-orin-nx-debug;
    nvidia-jetson-orin-agx-debug-bpmp-from-x86_64.x86_64-linux = mkBpmpEnabled self.nixosConfigurations.nvidia-jetson-orin-agx-debug-from-x86_64;
    nvidia-jetson-orin-agx64-debug-bpmp-from-x86_64.x86_64-linux = mkBpmpEnabled self.nixosConfigurations.nvidia-jetson-orin-agx64-debug-from-x86_64;
    nvidia-jetson-orin-nx-debug-bpmp-from-x86_64.x86_64-linux = mkBpmpEnabled self.nixosConfigurations.nvidia-jetson-orin-nx-debug-from-x86_64;
  };
}
