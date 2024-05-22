# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.development.ssh.daemon;
  inherit ((import ./authorized_ssh_keys.nix)) authorizedKeys;
  inherit (lib) mkEnableOption mkIf;
in {
  options.ghaf.development.ssh.daemon = {
    enable = mkEnableOption "ssh daemon";
  };

  config = mkIf cfg.enable {
    services.openssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = authorizedKeys;
    users.users.${config.ghaf.users.accounts.user}.openssh.authorizedKeys.keys = authorizedKeys;
  };
}
