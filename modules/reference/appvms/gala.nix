# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
{
  name = "gala";
  packages = [ pkgs.gala-app ];
  macAddress = "02:00:00:03:06:01";
  ramMb = 1536;
  cores = 2;
  extraModules = [
    {
      time.timeZone = config.time.timeZone;
      security.pki.certificateFiles = lib.mkIf config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable [
        ../../../modules/microvm/virtualization/microvm/idsvm/mitmproxy/mitmproxy-ca/mitmproxy-ca-cert.pem
      ];
    }
  ];
  borderColor = "#027d7b";
}
