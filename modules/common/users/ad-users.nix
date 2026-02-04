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
    ;
in
{
  _file = ./ad-users.nix;

  options.ghaf.users.adUsers = {
    enable = mkEnableOption "Active Directory user configuration";
  };

  config = {

    # Enable SSSD for Active Directory integration
    ghaf.services.sssd = {
      inherit (cfg) enable;
      debugLevel = 6;
      inherit (config.ghaf.users.active-directory) domains;
    };

    # TODO: Move this to profile config
    # Active Directory domain test configuration
    ghaf.users.active-directory.domains = {
      "ghaf-test.com" = {
        description = "Active Directory test domain";
        authProvider = "krb5";
        idProvider = "ad";
        dnsProvider = {
          name = "vm-ghaf-dev-dc.ghaf-test.com";
          ipAddress = "10.52.33.4";
        };
        ad = {
          domain = "ghaf-test.com";
          controllers = [ "vm-ghaf-dev-dc.ghaf-test.com" ];
          gpoAccessControl = "permissive";
          dyndnsUpdate = false;
        };
        krb5 = {
          realm = "GHAF-TEST.COM";
          server = [ "vm-ghaf-dev-dc.ghaf-test.com" ];
          kpasswd = [ "vm-ghaf-dev-dc.ghaf-test.com" ];
        };
        ldap = {
          uri = [ "ldap://vm-ghaf-dev-dc.ghaf-test.com" ];
          schema = "ad";
          idMapping = false;
          extraConfig = ''
            # RFC2307 User and group attribute mappings
            ldap_user_name = uid
            ldap_user_uid_number = uidNumber
            ldap_user_gid_number = gidNumber
            ldap_user_home_directory = homeDirectory
            ldap_user_shell = loginShell
          '';
        };
      };
    };
  };
}
