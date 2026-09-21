# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared option set for one Active Directory domain, mounted only by
# ghaf.users.active-directory.domains.<name> (modules/common/users/active-directory/default.nix).
# ghaf.org.identity.activeDirectory carries domains as deferred modules, so the
# defaults and derivations below are applied here, once: a leaf no one defined
# stays undefined and a direct definition refines the org's leaf by leaf.
# Keep this file options-only plus derivation defaults.
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
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

    useFullyQualifiedNames = mkEnableOption "fully qualified names (e.g., user@DOMAIN) for user accounts";

    enableGlobalCatalog = mkEnableOption "use of the Active Directory Global Catalog for this domain";

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
      dyndnsUpdate = mkEnableOption "automatic DNS record updates in AD for this client";
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
      useStartTls = mkEnableOption "StartTLS for LDAP connections for ldap:// URIs";
      enableSasl = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable SASL (GSSAPI) authentication for LDAP. Defaults to true.

          This option is currently enabled by default because the enrollment tooling
          only provisions GSSAPI today; another mechanism can be wired up but requires
          changes to the tooling to support it.
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

  # Conventional AD deployment values derived from the domain and controllers;
  # any explicit definition outranks them.
  config = {
    description = lib.mkDefault (
      if config.ad.domain != null then
        "Active Directory domain ${config.ad.domain}"
      else
        "Default AD domain"
    );
    krb5 = {
      realm = lib.mkDefault (if config.ad.domain != null then lib.toUpper config.ad.domain else null);
      server = lib.mkDefault config.ad.controllers;
      kpasswd = lib.mkDefault config.ad.controllers;
    };
    ldap.uri = lib.mkDefault (map (c: "ldap://${c}") config.ad.controllers);
  };
}
