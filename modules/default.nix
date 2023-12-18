# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
_: {
  flake.nixosModules = {
    development = import ./development;
    framework = import ./framework;
    graphics = import ./graphics;
    hardware.definition = import ./hardware/definition.nix;
    hardware.nvidia = import ./hardware/nvidia-jetson-orin;
    hardware.polarfire = import ./hardware/polarfire;
    hardware.x86_64-linux.common = import ./hardware/x86_64-linux;
    host.nvidia = import ./host/nvidia;
    host.polarfire = import ./host/polarfire;
    host.x86_64-linux = import ./host/x86_64-linux;
    host.networking = import ./host/networking.nix;
    installer = import ./installer;
    profiles = import ./profiles;
    programs = import ./programs;
    users = import ./users;
    virtualization.docker = import ./virtualization/docker.nix;
    virtualization.microvm = import ./virtualization/microvm;
    windows-launcher = import ./windows-launcher;
  };
}
