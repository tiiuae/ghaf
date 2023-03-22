# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  microvm,
  netvm,
}: {modulesPath, ...}: {
  imports = [
    (modulesPath + "/profiles/minimal.nix")

    microvm.nixosModules.host

    (import ./microvm.nix {inherit self netvm;})
    ./networking.nix
  ];

  networking.hostName = "ghaf-host";
  system.stateVersion = "22.11";

  # PCI passthrough needs larger locked-in-memory space than default
  systemd.services."microvm@".serviceConfig.LimitMEMLOCK = 999999999;
}
