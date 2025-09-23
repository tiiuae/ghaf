# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
  options.ghaf.reference.personalize.keys = {
    enable = mkEnableOption "Enable personalization of keys for dev team";
  };

  config = mkIf cfg.enable {
    users.users.root.openssh.authorizedKeys.keys = cfg.authorizedSshKeys;
    users.users.${config.ghaf.users.admin.name}.openssh.authorizedKeys.keys = cfg.authorizedSshKeys;
  };
}
