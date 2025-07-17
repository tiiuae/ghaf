# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial-extras;
in
{
  imports = [ ./mvp-user-trial.nix ];

  options.ghaf.reference.profiles.mvp-user-trial-extras = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      reference = {
        profiles = {
          mvp-user-trial.enable = true;
        };

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
          autologinUser = lib.mkForce null;
        };
      };

      # Enable audit
      security.audit.enable = lib.mkForce true;
    };
  };
}
