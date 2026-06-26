# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users.adUsers;
  inherit (lib)
    mkEnableOption
    mkIf
    ;
in
{
  _file = ./ad-users.nix;

  options.ghaf.users.adUsers = {
    enable = mkEnableOption "Active Directory user configuration";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.ghaf.users.active-directory.domains != { };
        message = ''
          The Active Directory users profile requires at least one
          ghaf.users.active-directory.domains entry.
        '';
      }
    ];

    # Enable SSSD for Active Directory integration
    ghaf.services.sssd = {
      enable = true;
      debugLevel = 6;
      inherit (config.ghaf.users.active-directory) domains;
    };
  };
}
