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
    types
    mkOption
    mkEnableOption
    mkIf
    ;
in
{
  options.ghaf.users.adUsers = {
    enable = mkEnableOption "Active Directory users";
    uids = mkOption {
      description = "UIDs for the Active Directory users.";
      type = types.listOf types.int;
      default = [ 1000 ];
    };
  };

  config = mkIf cfg.enable {
    ghaf.services.sssd = {
      enable = true;
      debugLevel = 6;
      domains = {
        "example.com" = {
          description = "Active Directory test domain";
          idProvider = "ad";
          authProvider = "ad";
          accessProvider = "ad";
          chpassProvider = "ad";
          dnsProvider = {
            name = "example-dc1.example.com";
            ipAddress = "10.10.10.10";
          };
          ad = {
            domain = "example.com";
            controllers = [ "example-dc1.example.com" ];
            gpoAccessControl = "permissive";
            dyndnsUpdate = false;
          };
          ldap = {
            uri = [ "ldap://example-dc1.example.com" ];
            schema = "ad";
            idMapping = false;
            extraConfig = ''
              ldap_sasl_mech = GSSAPI
              ldap_user_name = sAMAccountName
              ldap_user_principal = userPrincipalName
              ldap_user_uid_number = uidNumber
              ldap_user_gid_number = gidNumber
              ldap_user_home_directory = homeDirectory
              ldap_user_shell = loginShell
            '';
          };
        };
      };
    };
  };
}
