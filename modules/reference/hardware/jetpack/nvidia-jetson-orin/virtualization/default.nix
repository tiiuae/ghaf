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
  configuredGuiVmm = config.ghaf.virtualization.vmConfig.sysvms.guivm.vmm or null;
  guiVmm =
    if configuredGuiVmm == null then
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm
    else
      configuredGuiVmm;
  unifyingReceiver = {
    vendorId = "046d";
    productId = "c52b";
    description = "Logitech Unifying Receiver: evdev-only with the QEMU rollback";
  };
in
{
  _file = ./default.nix;

  imports = [
    ./host/uarta-host
    ./passthrough/uarti-net-vm
    ./passthrough/mgbe0-net-vm
    ./passthrough/gpu-display
    ./crosvm-shutdown.nix
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

    ghaf.hardware.passthrough.usb.guivmDeny =
      lib.mkIf config.ghaf.hardware.nvidia.passthroughs.gui_vm.enable
        (lib.optional (guiVmm != "crosvm") unifyingReceiver);
  };
}
