# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: let
  pciDevSubmodule = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        description = ''
          PCI device path
        '';
      };
      vendorId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          PCI Vendor ID (optional)
        '';
      };
      productId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          PCI Product ID (optional)
        '';
      };
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          PCI device name (optional)
        '';
      };
    };
  };
in {
  options.ghaf.graphics.hardware = {
    networkDevices = lib.mkOption {
      description = "Network PCI Devices";
      type = lib.types.listOf pciDevSubmodule;
      default = [];
      example = lib.literalExpression ''
        [{
          path = "0000:00:14.3";
          vendorId = "8086";
          productId = "51f1";
        }]
      '';
    };
  };
}
