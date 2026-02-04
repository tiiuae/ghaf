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
  _file = ./active-directory.nix;

  options.ghaf.users.active-directory = {

    domains = mkOption {
      description = "Active Directory domain configurations.";
      default = { };
      type = types.attrsOf (
        types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              default = "Default AD domain";
              description = "A short description of the domain.";
            };

            idProvider = mkOption {
              type = types.enum [
                "ldap"
                "ipa"
                "ad"
                "proxy"
              ];
              default = "ad";
              description = "Identity provider for the domain.";
            };

            authProvider = mkOption {
              type = types.enum [
                "ldap"
                "krb5"
                "ipa"
                "ad"
                "idp"
                "proxy"
                "none"
              ];
              default = "krb5";
              description = "Authentication provider for the domain.";
            };

            accessProvider = mkOption {
              type = types.enum [
                "ldap"
                "krb5"
                "ipa"
                "ad"
                "simple"
                "permit"
              ];
              default = "ad";
              description = "Access control provider for the domain.";
            };

            chpassProvider = mkOption {
              type = types.enum [
                "ldap"
                "krb5"
                "ipa"
                "ad"
              ];
              default = "ad";
              description = "Password change provider for the domain.";
            };

            dnsProvider = mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    name = mkOption {
                      type = types.str;
                      default = "";
                      description = "Name of the DNS provider for the domain.";
                    };
                    ipAddress = mkOption {
                      type = types.str;
                      default = "";
                      description = "IP address of the DNS server for the domain.";
                    };
                  };
                }
              );
              default = null;
              description = "DNS provider for the domain.";
            };

            useFullyQualifiedNames = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Whether to use fully qualified names (e.g., user@DOMAIN) for user accounts.
                Note that the behavior is different depending on the identity provider used.
                A value of 'false' may break functionality in multi-domain setups.
              '';
            };

            enableGlobalCatalog = mkOption {
              type = types.bool;
              default = false;
              description = "Enable use of the Active Directory Global Catalog for this domain.";
            };

            cacheCredentials = mkOption {
              type = types.bool;
              default = true;
              description = "Cache user credentials for offline logins.";
            };

            entryCacheTimeout = mkOption {
              type = types.int;
              default = 5400;
              description = "How many seconds should nss_sss consider entries valid before asking the backend again.";
            };

            minId = mkOption {
              type = types.int;
              default = 1;
              description = "Minimum UID and GID for this domain. Defaults to 1.";
            };

            maxId = mkOption {
              type = types.int;
              default = 0;
              description = "Maximum UID and GID for this domain. Defaults to no limit (0).";
            };

            extraConfig = mkOption {
              type = types.nullOr types.lines;
              default = null;
              description = "Additional domain configuration options.";
            };

            ad = {
              domain = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "The Active Directory domain name.";
                example = "corp.example.com";
              };
              controllers = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "List of Active Directory domain controllers.";
              };
              gpoAccessControl = mkOption {
                type = types.enum [
                  "permissive"
                  "enforcing"
                  "disabled"
                ];
                default = "permissive";
                description = ''
                  Use AD Group Policy Objects (GPOs) to control who can log in.
                  `permissive`: Users are allowed unless explicitly denied by a GPO.
                  `enforcing`: Users are denied unless explicitly allowed by a GPO.
                '';
              };
              dyndnsUpdate = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to automatically update DNS records in AD for this client.";
              };
              extraConfig = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Additional Active Directory configuration options.";
              };
            };

            ldap = {
              uri = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "List of LDAP server URIs.";
              };
              baseDn = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "The default search base for LDAP queries.";
              };
              tlsReqcert = mkOption {
                type = types.nullOr (
                  types.enum [
                    "allow"
                    "try"
                    "demand"
                    "hard"
                  ]
                );
                default = "allow";
                example = "hard";
                description = "TLS certificate checking policy.";
              };
              tlsCaCert = mkOption {
                type = types.nullOr types.lines;
                default = null;
                example = ''
                  -----BEGIN CERTIFICATE-----
                  [ Your CA certificate here ]
                  -----END CERTIFICATE-----
                '';
                description = ''
                  CA certificate for LDAP TLS as multi-line string. This will get added to
                  the global certificate store at '/etc/ssl/certs/ca-certificates.crt'.
                '';
              };
              useStartTls = mkOption {
                type = types.bool;
                default = false;
                description = "Use StartTLS for LDAP connections for ldap:// URIs. Requires tlsCaCert to be set.";
              };
              enableSasl = mkOption {
                type = types.bool;
                default = true;
                description = ''
                  Enable SASL (GSSAPI) authentication for LDAP. Defaults to true.
                '';
                readOnly = true;
              };
              schema = mkOption {
                type = types.nullOr (
                  types.enum [
                    "rfc2307"
                    "rfc2307bis"
                    "ipa"
                    "ad"
                  ]
                );
                default = null;
                example = "ad";
                description = "LDAP schema to use.";
              };
              idMapping = mkOption {
                type = types.bool;
                default = false;
                example = true;
                description = "Enable or disable the ID mapping feature. Useful for AD integration without POSIX attributes.";
              };
              extraConfig = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Additional LDAP configuration options.";
              };
            };

            krb5 = {
              server = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "List of Kerberos KDC servers.";
              };
              realm = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "The Kerberos realm.";
              };
              kpasswd = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "List of Kerberos kpasswd servers for password changes.";
              };
              extraConfig = mkOption {
                type = types.nullOr types.lines;
                default = null;
                description = "Additional Kerberos configuration options.";
              };
            };
          };
        }
      );
    };
  };

  config = mkIf (cfg.domains != { }) {

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
      dns = map (name: cfg.domains.${name}.dnsProvider.ipAddress) dnsDomains;
      domains = map (name: "~${name}") (lib.attrNames cfg.domains);
    };
  };

}
