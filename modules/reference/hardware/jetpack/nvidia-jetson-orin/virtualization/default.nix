# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.crosvm;
  managedVmsUseCrosvm = lib.all (
    vm: vm.type == "crosvm"
  ) config.ghaf.hardware.passthrough.vhotplug.vms;
in
{
  _file = ./default.nix;

  imports = [
    ./host/uarta-host
    ./passthrough/uarti-net-vm
    ./passthrough/mgbe0-net-vm
  ];

  options.ghaf.hardware.nvidia.orin.crosvm.enable =
    lib.mkEnableOption "Crosvm defaults for supported Orin targets";

  config = lib.mkIf cfg.enable {
    ghaf.virtualization.vmConfig = {
      defaultSysVmVmm = lib.mkDefault "crosvm";
      defaultAppVmVmm = lib.mkDefault "crosvm";
    };

    ghaf.hardware.passthrough.deviceManager.backend = lib.mkDefault (
      if managedVmsUseCrosvm then "ghaf-device-manager" else "vhotplug"
    );

    nixpkgs.overlays = [ inputs.self.overlays.crosvm-ghaf ];
  };
}
