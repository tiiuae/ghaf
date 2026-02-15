# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib)
    mkIf
    mkMerge
    ;

  # Qemu arguments for single device
  qemuArgsForSingleDevice =
    dev:
    if ((dev.vendorId != null) && (dev.productId != null)) then
      [
        "-device"
        "qemu-xhci"
        "-device"
        "usb-host,vendorid=0x${dev.vendorId},productid=0x${dev.productId},id=${dev.name}"
      ]
    else if ((dev.hostbus != null) && (dev.hostport != null)) then
      [
        "-device"
        "qemu-xhci"
        "-device"
        "usb-host,hostbus=${dev.hostbus},hostport=${dev.hostport},id=${dev.name}"
      ]
    else
      throw ''
        The internal USB device (name: ${dev.name or "unknown"}) is configured incorrectly.
        Please provide either vendorId and productId or hostbus and hostport.
      '';

  # VM udev rules for single device
  vmUdevRuleForSingleDevice =
    dev:
    if (dev.vmUdevExtraRule != null) then
      [
        "${dev.vmUdevExtraRule}"
      ]
    else
      [ ];

  vmNames = builtins.attrNames config.ghaf.hardware.passthrough.VMs;

  # Group devices by the VM name
  permittedDevicesByVm = builtins.listToAttrs (
    map (vm: {
      name = vm;
      value = builtins.filter (
        dev: builtins.elem dev.name config.ghaf.hardware.passthrough.VMs.${vm}.permittedDevices
      ) config.ghaf.hardware.definition.usb.devices;
    }) vmNames
  );

  qemuExtraArgsUSB = lib.mapAttrs (
    _vmName: devicesForThisVm: lib.concatMap qemuArgsForSingleDevice devicesForThisVm
  ) permittedDevicesByVm;

  vmUdevExtraRulesUSB =
    let
      allRulesPerVm = lib.mapAttrs (
        _vmName: devicesForThisVm: lib.concatMap vmUdevRuleForSingleDevice devicesForThisVm
      ) permittedDevicesByVm;
    in
    lib.filterAttrs (_vmName: rulesList: rulesList != [ ]) allRulesPerVm;

  extraRules =
    let
      generateRule =
        dev:
        if ((dev.vendorId != null) && (dev.productId != null)) then
          ''SUBSYSTEM=="usb", ATTR{idVendor}=="${dev.vendorId}", ATTR{idProduct}=="${dev.productId}", GROUP="kvm"''
        else if ((dev.hostbus != null) && (dev.hostport != null)) then
          ''KERNEL=="${dev.hostbus}-${dev.hostport}", SUBSYSTEM=="usb", ATTR{busnum}=="${dev.hostbus}", GROUP="kvm"''
        else
          throw ''
            The internal USB device is configured incorrectly.
                  Please provide name, and either vendorId and productId or hostbus and hostport.'';
    in
    lib.strings.concatMapStringsSep "\n" generateRule config.ghaf.hardware.definition.usb.devices;

  vhotplugUsbRules = map (vm: {
    targetVm = vm;
    description = "Static devices for ${vm}";
    allow = map (dev: {
      description = dev.name;
      bus = if dev.hostbus != null then lib.toIntBase10 dev.hostbus else null;
      port = if dev.hostport != null then lib.toIntBase10 dev.hostport else null;
      inherit (dev) vendorId;
      inherit (dev) productId;
    }) permittedDevicesByVm."${vm}";
  }) vmNames;
in
{
  _file = ./usb-static.nix;

  config = mkMerge [
    (mkIf
      (
        config.ghaf.hardware.passthrough.mode == "static"
        && builtins.length config.ghaf.hardware.definition.usb.devices > 0
      )
      {
        ghaf.hardware.passthrough = {
          qemuExtraArgs = qemuExtraArgsUSB;
        };

        # Host udev rules for internal USB devices
        services.udev = {
          inherit extraRules;
        };
      }
    )
    (mkIf (config.ghaf.hardware.passthrough.mode == "dynamic") {
      ghaf.hardware.passthrough.vhotplug.postpendUsbRules = vhotplugUsbRules;
    })
    {
      ghaf.hardware.passthrough.vmUdevExtraRules = vmUdevExtraRulesUSB;
    }
  ];
}
