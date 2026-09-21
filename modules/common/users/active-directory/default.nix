# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users.active-directory;

  inherit (lib)
    foldr
    mkIf
    mkOption
    recursiveUpdate
    types
    ;

  # Helpers
  dnsDomains = lib.filter (name: cfg.domains.${name}.dnsProvider != null) (lib.attrNames cfg.domains);
  inherit (config.ghaf.networking.hosts.${config.networking.hostName}) interfaceName;

in
{
  _file = ./default.nix;

  options.ghaf.users.active-directory = {

    domains = mkOption {
      description = "Active Directory domain configurations.";
      default = { };
      type = types.attrsOf (
        types.submoduleWith {
          modules = [ ./options.nix ];
        }
      );
    };
  };

  # Gated on the capability, not on the data: org-forwarded domains alone must
  # not reconfigure DNS or the trust store on images that never enable AD login.
  config = mkIf (config.ghaf.users.adUsers.enable && cfg.domains != { }) {

    # Limited domain configuration sanity checks
    assertions = lib.flatten (
      map (name: [
        {
          assertion = cfg.domains.${name}.ad.domain != null;
          message = "Domain ${name} does not have 'ad.domain' set.";
        }
        {
          assertion =
            ((cfg.domains.${name}.authProvider == "krb5") || (cfg.domains.${name}.authProvider == "ad"))
            -> (cfg.domains.${name}.krb5.realm != null);
          message = "Domains using 'krb5' or 'ad' authProvider must have 'krb5.realm' set.";
        }
        {
          assertion =
            ((cfg.domains.${name}.idProvider == "ldap") || (cfg.domains.${name}.idProvider == "ad"))
            -> (cfg.domains.${name}.ldap.uri != [ ]);
          message = "Domains using 'ldap' or 'ad' idProvider must have 'ldap.uri' set.";
        }
        {
          assertion =
            (
              cfg.domains.${name}.ldap.useStartTls
              && (lib.any (uri: lib.strings.hasPrefix "ldap://" uri) cfg.domains.${name}.ldap.uri)
            )
            -> (cfg.domains.${name}.ldap.tlsCaCert != null);
          message = "Domains using LDAP StartTLS must have 'ldap.tlsCaCert' set.";
        }

        # Remove this if support in user provisioning is added
        {
          assertion = lib.any (
            dc: (lib.all (kdc: kdc == dc) cfg.domains.${name}.krb5.server)
          ) cfg.domains.${name}.ad.controllers;
          message = "The krb5 server must equal a domain controller for provisioning.";
        }
      ]) (lib.attrNames cfg.domains)
    );

    # Add LDAP TLS certificates into global cert store
    security.pki.certificates = map (
      d:
      "${lib.optionalString (cfg.domains.${d}.ldap.tlsCaCert != null)
        "${cfg.domains.${d}.ldap.tlsCaCert}"
      }"
    ) (lib.attrNames cfg.domains);

    # Setup DNS for domains with DNS providers
    networking.hosts = foldr recursiveUpdate { } (
      map (name: {
        "${cfg.domains.${name}.dnsProvider.ipAddress}" = [ "${cfg.domains.${name}.dnsProvider.name}" ];
      }) dnsDomains
    );
    systemd.network.networks."10-${interfaceName}" = {
      matchConfig.Name = interfaceName;
      networkConfig.DNSDefaultRoute = false;
      dns = map (name: cfg.domains.${name}.dnsProvider.ipAddress) dnsDomains;
      domains = map (name: "~${name}") (lib.attrNames cfg.domains);
    };
  };

}
