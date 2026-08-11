# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Unprotected debug SSH: a plain sshd relying on password + development authorizedKeys.
# For debug images only; ghaf.security.ssh.release is the hardened production posture.
{ config, lib, ... }:
let
  cfg = config.ghaf.security.ssh.debug;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./debug.nix;

  options.ghaf.security.ssh.debug.enable =
    mkEnableOption "unprotected debug SSH (password + development authorizedKeys; debug images only)";

  config = mkIf cfg.enable {
    services.openssh.enable = true;
    ghaf.firewall.attack-mitigation.ssh.enable = true;
  };
}
