# SPDX-License-Identifier: Apache 2.0
{
  self,
  system,
}: {config, ...}: {
  microvm.host.enable = true;

  # TODO: Get system from config.nixpkgs.hostPlatform;
  microvm.vms."netvm-${system}" = {
    flake = self;
    autostart = true;
  };
}
