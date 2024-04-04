# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: {
  imports = [
    ../../../../x86_64-generic/kernel/host/default.nix
    ../../../../x86_64-generic/kernel/guest/default.nix
  ];

  # baseline, virtualization and network hardening are
  # generic to all x86_64 devices
  config.ghaf.host.kernel.hardening.enable = true;
  config.ghaf.host.kernel.hardening.virtualization.enable = true;
  config.ghaf.host.kernel.hardening.networking.enable = true;
  config.ghaf.host.kernel.hardening.inputdevices.enable = true;
  # usb/debug hardening is host optional but required for -debug builds
  config.ghaf.host.kernel.hardening.usb.enable = true;
  config.ghaf.host.kernel.hardening.debug.enable = true;

  # guest VM kernel specific options
  config.ghaf.guest.kernel.hardening.enable = true;
  config.ghaf.guest.kernel.hardening.graphics.enable = true;

  # required to module test a module via top level configuration
  config.boot.loader.systemd-boot.enable = true;
  config.fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
  };
  config.system.stateVersion = lib.trivial.release;
}
