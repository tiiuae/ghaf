# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.ghaf.development.usb-serial;
  hasUsbAuthorization = lib.hasAttrByPath [
    "ghaf"
    "hardware"
    "usb"
    "authorization"
    "hostAllow"
  ] options;
  inherit (lib)
    concatMapStrings
    mkEnableOption
    mkIf
    mkMerge
    ;

  # Commonly used USB serial adapters
  usbSerialAdapters = [
    {
      vid = "0403";
      pid = "6001";
    } # FTDI FT232R
    {
      vid = "0403";
      pid = "6010";
    } # FTDI FT2232
    {
      vid = "10c4";
      pid = "ea60";
    } # Silicon Labs CP210x
    {
      vid = "1a86";
      pid = "7523";
    } # WCH CH340
  ];

  usbSerialHostAllow = map (adapter: {
    vendorId = adapter.vid;
    productId = adapter.pid;
  }) usbSerialAdapters;

  mkUdevRule =
    { vid, pid }:
    ''
      ACTION=="add", KERNEL=="ttyUSB[0-9]*", ATTRS{idVendor}=="${vid}", ATTRS{idProduct}=="${pid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="serial-getty@%k.service"
    '';
in
{
  _file = ./usb-serial.nix;

  options.ghaf.development.usb-serial.enable = mkEnableOption "USB serial connection";

  #TODO Should this be alos bound to only x86?
  config = mkIf cfg.enable (mkMerge [
    {
      services.getty.extraArgs = [ "115200" ];
      systemd.services."serial-getty@".enable = true;

      services.udev.extraRules = concatMapStrings mkUdevRule usbSerialAdapters;
    }

    (lib.optionalAttrs hasUsbAuthorization {
      ghaf.hardware.usb.authorization.hostAllow = usbSerialHostAllow;
    })
  ]);
}
