# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.sssd;

  inherit (lib)
    boolToString
    concatMapStrings
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optionalString
    optionalAttrs
    types
    ;

  # Helpers
  hasStorageVM = config.ghaf.storagevm.enable;
  hasKcm = lib.any (d: (d.cacheCredentials && (d.authProvider == "krb5" || d.authProvider == "ad"))) (
    lib.attrValues cfg.domains
  );
  hasKerberosRealm = lib.any (d: d.krb5.realm != null) (lib.attrValues cfg.domains);

  # SSSD configuration template
  sssdConfig = ''
    [sssd]
    services = ${lib.concatStringsSep ", " cfg.services}
    domains = ${lib.concatStringsSep ", " (lib.attrNames cfg.domains)}
    ${optionalString (cfg.debugLevel != null) "debug_level = ${toString cfg.debugLevel}"}
    core_dumpable = false
    ${optionalString (cfg.extraConfig != null) "${cfg.extraConfig}"}

    [nss]
    filter_users = ${concatMapStrings (u: u + " ") (lib.attrNames config.users.users)}
    filter_groups = ${concatMapStrings (g: g + " ") (lib.attrNames config.users.groups)}
    ${optionalString (cfg.nss.homedirTemplate != null) "override_homedir = ${cfg.nss.homedirTemplate}"}
    ${optionalString (cfg.nss.shellOverride != null) "override_shell = ${cfg.nss.shellOverride}"}
    ${optionalString (cfg.nss.defaultShell != null) "default_shell = ${cfg.nss.defaultShell}"}
    entry_cache_nowait_percentage = ${toString cfg.entryCacheNowaitPercentage}
    ${optionalString (cfg.nss.extraConfig != null) "${cfg.nss.extraConfig}"}

    [pam]
    offline_credentials_expiration = ${toString cfg.pam.offlineCredentialsExpiration}
    offline_failed_login_attempts = ${toString cfg.pam.offlineFailedLoginAttempts}
    offline_failed_login_delay = ${toString cfg.pam.offlineFailedLoginDelay}
    pam_initgroups_scheme = ${cfg.pam.initGroupsScheme}
    pam_verbosity = 0
    ${optionalString (cfg.pam.extraConfig != null) "${cfg.pam.extraConfig}"}

    [kcm]
    ${optionalString (cfg.debugLevel != null) "debug_level = ${toString cfg.debugLevel}"}

    ${concatMapStrings (domainName: ''
      [domain/${domainName}]
      description = "${cfg.domains.${domainName}.description}"
      cache_credentials = ${boolToString cfg.domains.${domainName}.cacheCredentials}
      entry_cache_timeout = ${toString cfg.domains.${domainName}.entryCacheTimeout}
      use_fully_qualified_names = ${boolToString cfg.domains.${domainName}.useFullyQualifiedNames}
      offline_timeout = 30
      offline_timeout_random_offset = 10
      offline_timeout_max = 120

      ${optionalString (
        cfg.domains.${domainName}.extraConfig != null
      ) "${cfg.domains.${domainName}.extraConfig}"}

      # Kerberos Settings
      ${optionalString (cfg.domains.${domainName}.authProvider == "krb5") "krb5_validate = true"}
      ${optionalString (
        cfg.domains.${domainName}.authProvider == "krb5"
      ) "krb5_store_password_if_offline = ${boolToString cfg.domains.${domainName}.cacheCredentials}"}
      ${optionalString (cfg.domains.${domainName}.krb5.realm != null)
        "krb5_realm = ${cfg.domains.${domainName}.krb5.realm}"
      }
      ${optionalString (cfg.domains.${domainName}.krb5.server != [ ])
        "krb5_server = ${lib.concatStringsSep "," cfg.domains.${domainName}.krb5.server}"
      }
      ${optionalString (cfg.domains.${domainName}.krb5.kpasswd != [ ])
        "krb5_kpasswd = ${lib.concatStringsSep "," cfg.domains.${domainName}.krb5.kpasswd}"
      }

      # Service Providers
      id_provider = ${cfg.domains.${domainName}.idProvider}
      auth_provider = ${cfg.domains.${domainName}.authProvider}
      access_provider = ${cfg.domains.${domainName}.accessProvider}
      chpass_provider = ${cfg.domains.${domainName}.chpassProvider}

      # UID and GID ranges
      min_id = ${toString cfg.domains.${domainName}.minId}
      max_id = ${toString cfg.domains.${domainName}.maxId}

      # Active Directory Settings
      ${optionalString (cfg.domains.${domainName}.ad.domain != null) ''
        ad_domain = ${cfg.domains.${domainName}.ad.domain}
        ad_server = ${lib.concatStringsSep "," cfg.domains.${domainName}.ad.controllers}
        ad_gpo_access_control = ${cfg.domains.${domainName}.ad.gpoAccessControl}
        ad_enable_gc = ${boolToString cfg.domains.${domainName}.enableGlobalCatalog}
        dyndns_update = ${boolToString cfg.domains.${domainName}.ad.dyndnsUpdate}
      ''}
      ${optionalString (
        cfg.domains.${domainName}.ad.extraConfig != null
      ) "${cfg.domains.${domainName}.ad.extraConfig}"}

      # LDAP Settings
      ${optionalString (cfg.domains.${domainName}.ldap.uri != [ ])
        "ldap_uri = ${lib.concatStringsSep "," cfg.domains.${domainName}.ldap.uri}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.baseDn != null)
        "ldap_search_base = ${cfg.domains.${domainName}.ldap.baseDn}"
      }
      ${optionalString cfg.domains.${domainName}.ldap.enableSasl "ldap_sasl_mech = GSSAPI"}
      ldap_id_mapping = ${boolToString cfg.domains.${domainName}.ldap.idMapping}
      ${optionalString (cfg.domains.${domainName}.ldap.schema != null)
        "ldap_schema = ${cfg.domains.${domainName}.ldap.schema}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.tlsReqcert != null)
        "ldap_tls_reqcert = ${cfg.domains.${domainName}.ldap.tlsReqcert}"
      }
      ${optionalString (
        cfg.domains.${domainName}.ldap.tlsCaCert != null
      ) "ldap_tls_cacert = /etc/ssl/certs/ca-certificates.crt"}
      ldap_id_use_start_tls = ${boolToString cfg.domains.${domainName}.ldap.useStartTls}

      ${optionalString (
        cfg.domains.${domainName}.ldap.extraConfig != null
      ) "${cfg.domains.${domainName}.ldap.extraConfig}"}

    '') (lib.attrNames cfg.domains)}
  '';

in
{
  _file = ./sssd.nix;

  options.ghaf.services.sssd = {
    enable = mkEnableOption "SSSD service for Active Directory and LDAP user integration";

    debugLevel = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "SSSD debug level. Higher values are more verbose.";
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [
        "nss"
        "pam"
      ];
      description = "List of services SSSD should provide.";
    };

    entryCacheNowaitPercentage = mkOption {
      type = types.int;
      default = 50;
      description = "The percentage of the cache timeout after which SSSD will return a cached entry immediately and then update it.";
    };

    extraConfig = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = "Additional SSSD configuration options.";
    };

    domains = mkOption {
      type = types.attrs;
      default = { };
      description = "Active Directory configurations for SSSD.";
    };

    nss = {
      homedirTemplate = mkOption {
        type = types.nullOr types.str;
        default = "/home/%u";
        description = "Home directory template.";
      };
      shellOverride = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Shell override for user sessions.";
      };
      defaultShell = mkOption {
        type = types.nullOr types.str;
        default = "/run/current-system/sw/bin/bash";
        description = "Default shell for user sessions.";
      };
      extraConfig = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Additional NSS configuration options.";
      };
    };

    pam = {
      offlineCredentialsExpiration = mkOption {
        type = types.int;
        default = 7;
        description = "Number of days after which offline credentials expire.";
      };
      offlineFailedLoginAttempts = mkOption {
        type = types.int;
        default = 3;
        description = "Number of failed login attempts before the account is locked.";
      };
      offlineFailedLoginDelay = mkOption {
        type = types.int;
        default = 5;
        description = "Delay in seconds before allowing another login attempt.";
      };
      displayManagerService = mkOption {
        type = types.nullOr types.str;
        default = "greetd";
        description = "The PAM service name for your display manager (e.g., 'gdm-password', 'greetd', 'sddm').";
        example = "greetd";
      };
      initGroupsScheme = mkOption {
        type = types.enum [
          "always"
          "no_session"
          "never"
        ];
        default = "never";
        description = "PAM initgroups scheme. Set to 'never' to disable automatic group initialization.";
      };
      extraConfig = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Additional PAM configuration options.";
      };
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.domains != { };
        message = "At least one domain must be defined when using the SSSD module.";
      }
    ];

    # Configure NSCD caching
    services.nscd = {
      config = ''
        server-user nscd
        enable-cache hosts yes
        positive-time-to-live hosts 0
        negative-time-to-live hosts 0
        shared hosts yes
        enable-cache passwd no
        enable-cache group no
        enable-cache netgroup no
        enable-cache services no
      '';
    };

    # Configure SSSD
    services.sssd = {
      enable = true;
      kcm = hasKcm;
      config = sssdConfig;
    };

    # SSSD service dependencies
    systemd.services.sssd = {
      before = [
        "greetd.service"
        "cosmic-greeter.service"
      ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    ghaf = mkMerge [
      {
        # Set individual hostname
        identity.vmHostNameSetter.enable = true;

        # Watch SSSD directory and krb5 keytab
        security.audit.extraRules = mkIf (!hasStorageVM) [
          "-w /var/lib/sss -p wa -k sssd"
          "-w /etc/krb5.keytab -p wa -k krb5"
        ];
      }

      (mkIf hasStorageVM {
        storagevm = {
          # SSSD persistent storage
          directories = [
            {
              directory = "/var/lib/sss";
              user = "root";
              group = "root";
              mode = "0755"; # TODO check minimal permissions (nss)
            }
          ];
          # Kerberos keytab storage
          files = [
            {
              file = "/etc/krb5.keytab";
              user = "root";
              group = "root";
              mode = "0600";
            }
          ];
        };
        security.audit.extraRules = [
          "-w ${config.ghaf.storagevm.mountPath}/var/lib/sss -p wa -k sssd"
          "-w ${config.ghaf.storagevm.mountPath}/etc/krb5.keytab -p wa -k krb5"
        ];
      })
    ];

    # PAM configuration for display manager
    security.pam.services = optionalAttrs (cfg.pam.displayManagerService != null) {
      "${cfg.pam.displayManagerService}" = {
        makeHomeDir = true;
        rules = {
          auth = {
            # Disable ccreds pam modules to avoid conflicts with SSSD
            ccreds-store.enable = lib.mkForce false;
            ccreds-validate.enable = lib.mkForce false;

            # Allow both unix and sss auth
            unix.control = lib.mkForce "sufficient";
            sss.control = lib.mkForce "sufficient";
          };
        };

        # Disable Kerberos pam modules
        rules.auth.krb5.enable = lib.mkForce false;
        rules.account.krb5.enable = lib.mkForce false;
        rules.password.krb5.enable = lib.mkForce false;
        rules.session.krb5.enable = lib.mkForce false;
      };
    };

    # Kerberos configuration '/etc/krb5.conf' auto-populated from domain settings
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

    # Override upstream KCM exec
    systemd.services.sssd-kcm.serviceConfig = {
      ExecStartPre = lib.mkForce "";
      ExecStart = lib.mkForce "${pkgs.sssd}/libexec/sssd/sssd_kcm";
    };
  };
}
