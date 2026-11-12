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
    optionalAttrs
    recursiveUpdate
    types
    ;

  # Helpers
  dnsDomains = lib.filter (name: cfg.domains.${name}.dnsProvider != null) (lib.attrNames cfg.domains);
  hasKerberosRealm = lib.any (d: d.krb5.realm != null) (lib.attrValues cfg.domains);
  hasKcm = config.services.sssd.enable && config.services.sssd.kcm;
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

  # Active when either AD login or homed user setup has configured domains.
  config =
    mkIf
      ((config.ghaf.users.adUsers.enable || config.ghaf.users.homedUser.enable) && cfg.domains != { })
      {

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

        ghaf.firewall =
          let
            ports = {
              kerberos = 88;
              ldap = 389;
              kpasswd = 464;
            };
            toDc = port: {
              inherit port;
              direction = "output";
              to = map (name: cfg.domains.${name}.dnsProvider.ipAddress) dnsDomains;
            };
          in
          mkIf (dnsDomains != [ ]) {
            allowedTCPPorts = map toDc (lib.attrValues ports);
            allowedUDPPorts = map toDc (lib.attrValues ports);
          };

        security.pam.krb5.enable = lib.mkDefault false;
        security.krb5 = optionalAttrs hasKerberosRealm {
          enable = true;
          settings = {
            libdefaults = {
              default_realm = lib.head (
                lib.filter (realm: realm != null) (map (d: cfg.domains.${d}.krb5.realm) (lib.attrNames cfg.domains))
              );
              default_ccache_name = if hasKcm then "KCM:" else "FILE:/run/user/%{uid}/krb5cc_%{uid}";
              dns_lookup_kdc = true;
              dns_lookup_realm = true;
            };
            realms = lib.listToAttrs (
              map (
                domainName:
                let
                  domain = cfg.domains.${domainName};
                  kdcServers = if domain.krb5.server != [ ] then domain.krb5.server else domain.ad.controllers;
                  adminServer =
                    if kdcServers != [ ] then
                      lib.head kdcServers
                    else
                      throw (
                        "Cannot determine admin_server for realm ${domain.krb5.realm} "
                        + "as no kdc or ad controllers are configured."
                      );
                in
                lib.nameValuePair "${domain.krb5.realm}" {
                  kdc = kdcServers;
                  admin_server = adminServer;
                  kpasswd_server = if domain.krb5.kpasswd != [ ] then domain.krb5.kpasswd else kdcServers;
                }
              ) (lib.filter (name: cfg.domains.${name}.krb5.realm != null) (lib.attrNames cfg.domains))
            );
            domain_realm = lib.listToAttrs (
              lib.flatten (
                map (
                  domainName:
                  let
                    domain = cfg.domains.${domainName};
                  in
                  if domain.ad.domain != null && domain.krb5.realm != null then
                    [
                      (lib.nameValuePair ".${domain.ad.domain}" domain.krb5.realm)
                      (lib.nameValuePair "${domain.ad.domain}" domain.krb5.realm)
                    ]
                  else
                    [ ]
                ) (lib.attrNames cfg.domains)
              )
            );
          };
        };
      };

}
