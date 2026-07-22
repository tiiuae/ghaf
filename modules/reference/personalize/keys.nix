# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.personalize.keys;
  inherit (lib)
    mkEnableOption
    mkIf
    ;
in
{
  _file = ./keys.nix;

  options.ghaf.reference.personalize.keys = {
    enable = mkEnableOption "personalization of keys for dev team";
  };

  config = mkIf cfg.enable {
    users.users.${config.ghaf.users.admin.name}.openssh.authorizedKeys.keys = cfg.authorizedSshKeys;

    # Root keeps the dev keys in debug images -- ghaf-rebuild deploys as root,
    # and a developer image is expected to hand over the machine. Gated on the
    # debug profile rather than on cfg.enable alone so that enabling this module
    # in a release composition cannot grant root a key: release must have no
    # root login at all (ghaf.security.ssh.release sets PermitRootLogin = "no",
    # and the assertion there enforces the pair).
    users.users.root.openssh.authorizedKeys.keys =
      mkIf config.ghaf.profiles.debug.enable cfg.authorizedSshKeys;
  };
}
