# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  inputs,
  config,
}:

vmName: cfg: baseConfig: {

  ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

  microvm.vms.${vmName} = {
    autostart = true;
    inherit (inputs) nixpkgs;
    specialArgs = { inherit lib; };
    config = baseConfig // {
      imports = baseConfig.imports ++ cfg.extraModules;

      ghaf.virtualization.microvm.vm-networking = {
        enable = true;
        inherit vmName;
      };
    };
  };

}
