# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  imports = [ ../default.nix ];

  # pkvm hardening is generic to all x86_64 devices
  config = {
    ghaf.host.kernel.hardening.hypervisor.enable = true;

    # required to module test a module via top level configuration
    boot.loader.systemd-boot.enable = true;
    fileSystems."/" = {
      device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
      fsType = "ext4";
    };
    system.stateVersion = lib.trivial.release;
  };
}
