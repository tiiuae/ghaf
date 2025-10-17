# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
{
  config = {
    ghaf.hardware.definition.usb.devices = [
      # Common list of external usb devices which are included
      # by default in hardware-x86_64-workstation, which we
      # can assign to any vm later depending on requirements.
      rec {
        name = "gps0";
        vendorId = "067b";
        productId = "23a3";
        vmUdevExtraRule = ''
          ACTION=="add", ENV{ID_BUS}=="usb", ENV{ID_VENDOR_ID}=="${vendorId}", ENV{ID_MODEL_ID}=="${productId}", ENV{DEVNAME}=="/dev/ttyUSB*", RUN+="${pkgs.gpsd}/bin/gpsdctl add '%E{DEVNAME}'"
        '';
      }
      # Logitech Gamepad F310
      {
        name = "xbox0";
        vendorId = "046d";
        productId = "c21d";
      }
      # Microsoft Corp. Xbox Controller
      {
        name = "xbox1";
        vendorId = "045e";
        productId = "0b12";
      }
      # Microsoft Corp. Xbox One wireless controller
      {
        name = "xbox2";
        vendorId = "045e";
        productId = "02ea";
      }
      # Crazyradio (normal operation)
      {
        name = "crazyradio0";
        vendorId = "1915";
        productId = "7777";
      }
      # Crazyradio bootloader
      {
        name = "crazyradio1";
        vendorId = "1915";
        productId = "0101";
      }
      # Crazyflie (over USB)
      {
        name = "crazyflie0";
        vendorId = "0483";
        productId = "5740";
      }
    ];
  };
}
