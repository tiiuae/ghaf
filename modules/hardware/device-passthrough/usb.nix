# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    mkIf
    mkMerge
    literalExpression
    ;

  # USB device submodule, defined either by product ID and vendor ID, or by bus and port number
  usbDevSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          USB device name. NOT optional for external devices, in which case it must not contain spaces
          or extravagant characters.
        '';
      };

      vmUdevExtraRule = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Extra udev rule for the VM to control access of the USB device.
        '';
      };

      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          USB Vendor ID (optional). If this is set, the productId must also be set.
        '';
      };
      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          USB Product ID (optional). If this is set, the vendorId must also be set.
        '';
      };

      # TODO: The use of hostbus and hostport is not a reliable way to identify the attached device,
      # as these values may change depending on the system's USB topology or reboots. Consider using
      # vendorId and productId for more stable identification. If this is not feasible, document the
      # scenarios where hostbus and hostport are acceptable and plan for a more robust solution.

      hostbus = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          USB device bus number (optional). If this is set, the hostport must also be set.
        '';
      };
      hostport = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          USB device device number (optional). If this is set, the hostbus must also be set.
        '';
      };
    };
  };
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
      builtins.throw ''
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
    builtins.map (vm: {
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
          builtins.throw ''
            The internal USB device is configured incorrectly.
                  Please provide name, and either vendorId and productId or hostbus and hostport.'';
    in
    lib.strings.concatMapStringsSep "\n" generateRule config.ghaf.hardware.definition.usb.devices;

  vhotplugRules = builtins.map (vm: {
    targetVm = vm;
    description = "Static devices for ${vm}";
    allow = builtins.map (dev: {
      description = dev.name;
      bus = if dev.hostbus != null then lib.toIntBase10 dev.hostbus else null;
      port = if dev.hostport != null then lib.toIntBase10 dev.hostport else null;
      inherit (dev) vendorId;
      inherit (dev) productId;
    }) permittedDevicesByVm."${vm}";
  }) vmNames;
in
{
  options.ghaf.hardware.passthrough.usb = {
    devices = mkOption {
      description = ''
        List of USB device(s) to passthrough.

        Each device definition requires a name, and either vendorId and productId, or hostbus and hostport.
        The latter is useful for addressing devices that may have different vendor and product IDs in the
        same hardware generation.

        Note that internal devices must follow the naming convention to be correctly identified
        and subsequently used. Current special names are:
          - 'cam0' for the internal cam0 device
          - 'fpr0' for the internal fingerprint reader device
      '';
      type = types.listOf usbDevSubmodule;
      default = [ ];
      example = literalExpression ''
        [
          {
            name = "cam0";
            vendorId = "0123";
            productId = "0123";
          }
          {
            name = "fpr0";
            hostbus = "3";
            hostport = "3";
          }
        ]
      '';
    };
  };
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
      ghaf.hardware.usb.vhotplug.postpendRules = vhotplugRules;
    })
    {
      ghaf.hardware.passthrough.vmUdevExtraRules = vmUdevExtraRulesUSB;
    }
  ];
}
