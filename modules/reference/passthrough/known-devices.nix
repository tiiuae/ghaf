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
  _file = ./known-devices.nix;

  options.ghaf.reference.passthrough.usb = {
    internalWebcams = mkOption {
      type = with types; listOf (attrsOf str);
      default = [ ];
      description = ''
        List of internal USB webcams.
      '';
    };

    fingerprintReaders = mkOption {
      type = with types; listOf (attrsOf str);
      default = [ ];
      description = ''
        List of fingerprint readers.
      '';
    };
  };

  config.ghaf.reference.passthrough.usb = {
    internalWebcams = [
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

    fingerprintReaders = [
      {
        vendorId = "06cb";
        productId = "00fc";
        description = "Synaptics, Inc. Prometheus Fingerprint Reader";
      }
    ];
  };
}
