# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}:
with lib; let
  pciDevSubmodule = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        description = ''
          PCI device path
        '';
      };
      vendorId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          PCI Vendor ID (optional)
        '';
      };
      productId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          PCI Product ID (optional)
        '';
      };
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          PCI device name (optional)
        '';
      };
    };
  };
in {
  options.ghaf.graphics.hardware = {
    networkDevices = mkOption {
      description = "Network PCI Devices";
      type = types.listOf pciDevSubmodule;
      default = [];
      example = literalExpression ''
        [{
          path = "0000:00:14.3";
          vendorId = "8086";
          productId = "51f1";
        }]
      '';
    };
  };
}
