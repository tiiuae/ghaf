# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Unprotected debug SSH: a plain sshd relying on password + development authorizedKeys.
# For debug images only; ghaf.security.ssh.release is the hardened production posture.
{ config, lib, ... }:
let
  cfg = config.ghaf.security.ssh.debug;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    types
    ;

  # Dev keys are a debug-image only; release does not enable root access
  installRootKeys = (config.ghaf.profiles.debug.enable or false) && cfg.authorizedKeys != [ ];
in
{
  _file = ./debug.nix;

  options.ghaf.security.ssh.debug = {
    enable = mkEnableOption "unprotected debug SSH (password + development authorizedKeys; debug images only)";

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Development-team SSH key roster, installed for root and the admin user
        on debug images. Normally org-supplied; direct definitions append to the org
        roster.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.openssh.enable = true;
    ghaf.firewall.attack-mitigation.ssh.enable = true;
    users.users = mkIf installRootKeys (
      {
        root.openssh.authorizedKeys.keys = cfg.authorizedKeys;
      }
      // optionalAttrs config.ghaf.users.admin.enable {
        ${config.ghaf.users.admin.name}.openssh.authorizedKeys.keys = cfg.authorizedKeys;
      }
    );
  };
}
