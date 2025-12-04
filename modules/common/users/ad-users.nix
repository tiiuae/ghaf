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
  options.ghaf.users.adUsers = {
    enable = mkEnableOption "Active Directory users";
  };

  config = mkIf cfg.enable {
    ghaf.services.sssd = {
      enable = true;
      debugLevel = 6;
      domains = {
        "example.com" = {
          description = "Active Directory test domain";
          autofsProvider = "ad";
          dnsProvider = {
            name = "example.com";
            ipAddress = "10.10.10.10";
          };
          ad = {
            domain = "example.com";
            controllers = [ "example.com" ];
            gpoAccessControl = "permissive";
            dyndnsUpdate = false;
          };
          krb5 = {
            realm = "EXAMPLE.COM";
            server = [ "example.com" ];
            kpasswd = [ "example.com" ];
          };
          ldap = {
            uri = [ "ldap://example.com" ];
            schema = "ad";
            idMapping = false;
            extraConfig = ''
              # General LDAP settings
              ldap_sasl_mech = GSSAPI
              # User and group attribute mappings
              ldap_user_name = sAMAccountName
              ldap_user_principal = userPrincipalName
              ldap_user_uid_number = uidNumber
              ldap_user_gid_number = gidNumber
              ldap_user_home_directory = homeDirectory
              ldap_user_shell = loginShell
              # Autofs configuration
              ldap_autofs_search_base = cn=automount,dc=example,dc=com
              ldap_autofs_map_object_class = nisMap
              ldap_autofs_map_name = nisMapName
              ldap_autofs_entry_object_class = nisObject
              ldap_autofs_entry_key = cn
              ldap_autofs_entry_value = nisMapEntry
            '';
          };
        };
      };
    };
  };
}
