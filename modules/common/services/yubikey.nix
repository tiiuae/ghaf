# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatStrings
    ;
  cfg = config.ghaf.services.yubikey;
in
{
  _file = ./yubikey.nix;

  options.ghaf.services.yubikey = {
    enable = mkEnableOption "the yubikey support which provide 2FA";

    u2fKeys = mkOption {
      type = types.str;
      default = [ ];
      example = concatStrings [
        ##  Key should in following format <username>:<KeyHandle1>,<UserKey1>,<CoseType1>,<Options1>:<KeyHandle2>,<UserKey2>,<CoseType2>,<Options2>:...
        "ghaf:SZ2CwN7EAE4Ujfxhm+CediUaT9ngoaMOqsKRDrOC+wUkTriKlc1cVtsxkOSav2r9ztaNKn/OwoHiN3BmsBYdZA==,oIdGgoGmkVrVis1kdzpvX3kXrOmBe2noFrpHqh4VKlq/WxrFk+Du670BL7DzLas+GxIPNjgdDCHo9daVzthIwQ==,es256,+presence"
        ":9CEdjOg0YGpvNeisK5OW1hjjg0nRvJDBpr7X8Q4QPtxJP4iC5C6dShTxEpxmLAkqAi8x/jKCDwpt146AYAXfFg==,q8ddSEI2tIyRwB2MhRlrGZRv6ZDkEC2RYn/n33fdmK1KjBkcMy6ELUMQQDVGtsvsiQFbRS3v4qxjsgXF5BVD0A==,es256,+presence+pin"
      ];
      description = "It will contain U2F Keys / public keys reterived from Yubikey hardware";
    };
  };

  config = mkIf cfg.enable {
    # Enable service and package for Yubikey
    services.pcscd.enable = true;
    environment.systemPackages = [
      pkgs.pam_u2f
    ];

    security.pam.services = {
      sudo.u2fAuth = true;
      gtklock.u2fAuth = true;
    };

    security.pam.u2f = {
      settings = {
        cue = true;
      };
      control = "sufficient";
    };

    # Below rules are needed for screen locker (gtklock) to work
    services.udev.extraRules = ''
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1050", ATTRS{idProduct}=="0407", TAG+="uaccess", GROUP="kvm", MODE="0666"
      ACTION=="remove", ENV{ID_BUS}=="usb", ENV{ID_VENDOR_ID}=="1050", ENV{ID_MODEL_ID}=="0407", RUN+="${pkgs.systemd}/bin/loginctl lock-sessions"
    '';

    givc.sysvm.capabilities.ctap.enable = true;
  };
}
