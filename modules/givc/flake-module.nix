# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, ... }:
{
  flake.nixosModules = {
    givc.imports = [
      inputs.givc.nixosModules.admin
      inputs.givc.nixosModules.host
      inputs.givc.nixosModules.tls
      inputs.givc.nixosModules.dbus
      inputs.givc.nixosModules.sysvm
      inputs.givc.nixosModules.appvm
      ./common.nix
      ./adminvm.nix
      ./host.nix
      ./guivm.nix
      ./netvm.nix
      ./audiovm.nix
      ./appvm.nix
    ];
  };
}
