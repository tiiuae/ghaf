# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.usb-serial;
  getty = config.services.getty;
  inherit (lib) mkEnableOption mkIf concatMapStrings;

  # The arguments NixOS's getty module passes to every agetty.
  gettyArgs = [
    "--login-program"
    "${getty.loginProgram}"
    "--issue-file"
    "/etc/issue:/etc/issue.d:/run/issue:/run/issue.d"
  ]
  ++ lib.optionals (getty.autologinUser != null && !getty.autologinOnce) [
    "--autologin"
    getty.autologinUser
  ]
  ++ lib.optionals (getty.loginOptions != null) [
    "--login-options"
    getty.loginOptions
  ];

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
  config = mkIf cfg.enable {
    # NixOS starts serial gettys without a baud rate. Set it on this unit only:
    # services.getty.extraArgs also reaches the VT gettys and corrupts their TERM.
    systemd.services."serial-getty@" = {
      enable = true;
      serviceConfig.ExecStart = lib.mkForce [
        ""
        "${lib.getExe' pkgs.util-linux "agetty"} ${lib.escapeShellArgs gettyArgs} %I 115200 $TERM"
      ];
    };

    services.udev.extraRules = concatMapStrings mkUdevRule usbSerialAdapters;
  };
}
