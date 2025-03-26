# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  config = {
    ghaf = {
      reference = {
        programs = {
          windows-launcher = {
            enable = true;
            spice = true;
          };
        };
      };

      profiles = {
        # Enable below option for host hardening features
        # Secure Boot
        host-hardening.enable = true;
      };

      virtualization.microvm = {
        # Enable idsvm and the MiTM features
        idsvm = {
          enable = lib.mkForce true;
          mitmproxy.enable = lib.mkForce true;
        };
      };

      # Enable below option for session lock feature
      graphics = {
        boot.enable = lib.mkForce true;
        labwc = {
          autolock.enable = lib.mkForce true;
          autologinUser = lib.mkForce null;
        };
      };
    };
  };
}
