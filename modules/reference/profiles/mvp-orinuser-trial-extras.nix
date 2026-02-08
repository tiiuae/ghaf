# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.profiles.mvp-orinuser-trial-extras;
in
{
  _file = ./mvp-orinuser-trial-extras.nix;

  imports = [ ./mvp-orinuser-trial.nix ];

  options.ghaf.reference.profiles.mvp-orinuser-trial-extras = {
    enable = lib.mkEnableOption "Enable the mvp orin configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      reference = {
        profiles = {
          mvp-orinuser-trial.enable = true;
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

      graphics = {
        # Plymouth doesn't work as it should on Orins
        boot.enable = lib.mkForce false;
      };

      # Enable audit
      security.audit.enable = lib.mkForce true;
    };
  };
}
