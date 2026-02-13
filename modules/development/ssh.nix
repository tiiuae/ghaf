# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.development.ssh.daemon;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./ssh.nix;

  options.ghaf.development.ssh.daemon.enable = mkEnableOption "ssh daemon";

  config = mkIf cfg.enable {

    services.openssh.enable = true;

    ghaf.firewall.attack-mitigation.ssh.enable = true;
  };
}
