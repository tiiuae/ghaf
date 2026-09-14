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
    enable = lib.mkEnableOption "the mvp Orin configuration for apps and services";
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
        # mitmproxy is deliberately left off: it REDIRECTs :80/:443 arriving on
        # the ids-vm's own interface, which only fires when app traffic is
        # routed through it. Passive GRE mirroring makes the VM a copy
        # destination rather than a gateway, so those rules cannot match.
        idsvm = {
          enable = lib.mkForce true;
          # Base Orin profile leaves this off; only the extras/trial image
          # turns passive monitoring on.
          passiveMonitor.enable = lib.mkForce true;
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
