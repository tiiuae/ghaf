# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    ;
in
{
  options.ghaf.hardware.usb.internal = {
    webcams = mkOption {
      type = with types; listOf (attrsOf str);
      default = [ ];
      example = [
        {
          vendorId = "04f2";
          productId = "b751";
          description = "Lenovo X1 Integrated Camera";
        }
        {
          vendorId = "04f2";
          productId = "b729";
          description = "System76 darp11-b Integrated Camera";
        }
      ];
      description = ''
        List of internal USB webcams with Vendor ID, Product ID and description.
      '';
    };
  };

  config = {
    ghaf.hardware.usb.internal.webcams = [
      {
        vendorId = "04f2";
        productId = "b751";
        description = "Lenovo X1 Integrated Camera (Finland SKU)";
      }
      {
        vendorId = "5986";
        productId = "2145";
        description = "Lenovo X1 Integrated Camera (UAE 1st SKU)";
      }
      {
        vendorId = "30c9";
        productId = "0052";
        description = "Lenovo X1 Integrated Camera (UAE #2 SKU)";
      }
      {
        vendorId = "30c9";
        productId = "005f";
        description = "Lenovo X1 gen 12 Integrated Camera (Finland SKU)";
      }
      {
        vendorId = "04f2";
        productId = "b729";
        description = "System76 darp11-b Integrated Camera";
      }
    ];
  };
}
