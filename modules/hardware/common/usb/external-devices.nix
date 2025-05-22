# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  config = {
    ghaf.hardware.definition.usb.external = [
      # Common list of external usb devices which are included
      # by default in hardware-x86_64-workstation, which we
      # can assign to any vm later depending on requirements.
      {
        name = "gps0";
        vendorId = "067b";
        productId = "23a3";
      }
      {
        name = "yubikey0";
        vendorId = "1050";
        productId = "0407";
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
    ];
  };
}
