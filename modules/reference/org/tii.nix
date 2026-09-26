# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TII reference org configuration.A downstream project may supply its own org module.
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.org.tii;
in
{
  _file = ./tii.nix;

  options.ghaf.reference.org.tii.enable = lib.mkEnableOption "TII reference org configuration";

  config = lib.mkIf cfg.enable {
    ghaf.org = {
      telemetry = {
        logging = {
          endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
          serverName = "loki.ghaflogs.vedenemo.dev";
        };
        bugReport = {
          owner = "tiiuae";
          repo = "ghaf-bugreports";
        };
      };
      management.fleet.url = "https://fleetdm.vedenemo.dev";
      network.firewallRulesUrl = "https://raw.githubusercontent.com/tiiuae/ghaf-policies/deploy/vm-policies/firewall-rules/iptables.rules";

      # TII's UEFI enrollment certificates (public PK/KEK/db halves only;
      # generated from tiiuae/ghaf-infra-pki, see the README beside them).
      pki.secureBootKeysSource = ./secureboot-keys;

      # TII development AD test domain (formerly hardcoded in ad-users.nix). Realm,
      # KDC servers and LDAP URIs derive from domain and controllers (active-directory/options.nix).
      identity.activeDirectory.domains."ghaf-test.com" = {
        ad = {
          domain = "ghaf-test.com";
          controllers = [ "vm-ghaf-dev-dc.ghaf-test.com" ];
        };
        dnsProvider = {
          name = "vm-ghaf-dev-dc.ghaf-test.com";
          ipAddress = "10.52.33.4";
        };
        ldap = {
          schema = "ad";
          # TII's AD publishes POSIX attributes; map them RFC2307-style
          # (idMapping stays false, the shared type's default).
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

      # Release images admit no org SSH keys yet; an empty list means
      # exactly that, and release test keys land here when TII issues them.
      identity.ssh.releaseKeys = [ ];

      identity.ssh.debugKeys = import ./tii-debug-keys.nix;
    };
  };
}
