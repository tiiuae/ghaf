# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # TODO rework the templates to match the new modules
  flake.templates = {
    # Module template
    ghaf-module = {
      path = ./modules;
      description = "A config to bootstrap a Ghaf compatible module";
    };

    # A Selection of targets that utilize Ghaf to define more feature rich
    # projects/products.

    # ARM targets
    target-aarch64-nvidia-orin-agx = {
      path = ./targets/aarch64/nvidia/orin-agx;
      description = "A Ghaf based configuration for the Nvidia Orin AGX";
    };
    target-aarch64-nvidia-orin-nx = {
      path = ./targets/aarch64/nvidia/orin-nx;
      description = "A Ghaf based configuration for the Nvidia Orin NX";
    };
    target-aarch64-nxp-imx8mp-evk = {
      path = ./targets/aarch64/nxp/imx8mp-evk;
      description = "A Ghaf based configuration for the NXP iMX8 MPlus";
    };

    # x86 targets
    target-x86_64-generic = {
      path = ./targets/x86_64/generic;
      description = "A Ghaf based configuration for x86_64 targets";
    };

    # RISC-v targets
    target-riscv64-microchip-polarfire = {
      path = ./targets/riscv64/microchip/polarfire;
      description = "A Ghaf based configuration for the Microchip Polarfire";
    };
  };
}
