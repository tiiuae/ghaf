# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.sssd;

  inherit (lib)
    boolToString
    foldr
    concatMapStrings
    mkEnableOption
    mkIf
    mkOption
    optionalString
    optionalAttrs
    recursiveUpdate
    types
    ;
  inherit (config.ghaf.networking.hosts.${config.networking.hostName}) interfaceName;

  # Problems
  # TODO AD join will use GUI-VM as hostname, add dynamic gui-vm hostname support?
  # TODO Password change policy from AD not supported by cosmic-greeter

  # Improvements
  # TODO Only single AD setup has been tested, enrollement only supports single domain
  # TODO Tune local_auth_policy and authentication policy, check [prompting/...] support

  # Features to add
  # TODO Add FIDO2 support + MFA
  # TODO Support autofs+nfs for AD users
  # TODO Add sudo provider / AD sudo support
  # TODO Evaluate FS encryption with SSSD
  # TODO Add group autojoin in PAM stack with SSSD, or remove groups
  # TODO Support TPM sealing for ldap bind pwd and keytabs
  # TODO Add more AD controls such as ad_gpo_map_interactive

  # SSSD configuration template
  sssdConfig = ''
    [sssd]
    services = ${lib.concatStringsSep ", " cfg.services}
    domains = ${lib.concatStringsSep ", " (lib.attrNames cfg.domains)}
    ${optionalString (cfg.debugLevel != null) "debug_level = ${toString cfg.debugLevel}"}
    core_dumpable = false
    ${optionalString (cfg.extraConfig != null) ''${cfg.extraConfig}''}

    [nss]
    filter_users = ${concatMapStrings (u: u + " ") (lib.attrNames config.users.users)}
    # filter_groups = ${concatMapStrings (g: g + " ") (lib.attrNames config.users.groups)}
    ${optionalString (cfg.nss.homedirTemplate != null) "override_homedir = ${cfg.nss.homedirTemplate}"}
    ${optionalString (cfg.nss.shellOverride != null) "override_shell = ${cfg.nss.shellOverride}"}
    ${optionalString (cfg.nss.defaultShell != null) "default_shell = ${cfg.nss.defaultShell}"}
    entry_cache_nowait_percentage = ${toString cfg.entryCacheNowaitPercentage}
    ${optionalString (cfg.nss.extraConfig != null) ''${cfg.nss.extraConfig}''}

    [pam]
    offline_credentials_expiration = ${toString cfg.pam.offlineCredentialsExpiration}
    offline_failed_login_attempts = ${toString cfg.pam.offlineFailedLoginAttempts}
    offline_failed_login_delay = ${toString cfg.pam.offlineFailedLoginDelay}
    ${optionalString (cfg.pam.extraConfig != null) ''${cfg.pam.extraConfig}''}

    ${concatMapStrings (domainName: ''
      [domain/${domainName}]
      description = "${cfg.domains.${domainName}.description}"
      cache_credentials = ${boolToString cfg.domains.${domainName}.cacheCredentials}
      entry_cache_timeout = ${toString cfg.domains.${domainName}.entryCacheTimeout}
      use_fully_qualified_names = false
      ad_enable_gc = true

      ${optionalString (
        cfg.domains.${domainName}.extraConfig != null
      ) ''${cfg.domains.${domainName}.extraConfig}''}

      # Kerberos Settings
      krb5_store_password_if_offline = true
      ${optionalString (cfg.domains.${domainName}.krb5.realm != "")
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
      autofs_provider = ${cfg.domains.${domainName}.autofsProvider}

      # UIDs
      min_id = ${toString cfg.domains.${domainName}.minId}
      max_id = ${toString cfg.domains.${domainName}.maxId}

      # Active Directory Settings
      ${optionalString (cfg.domains.${domainName}.ad.domain != null) ''
        ad_domain = ${cfg.domains.${domainName}.ad.domain}
        ad_server = ${lib.concatStringsSep "," cfg.domains.${domainName}.ad.controllers}
        ad_gpo_access_control = ${cfg.domains.${domainName}.ad.gpoAccessControl}
        dyndns_update = ${boolToString cfg.domains.${domainName}.ad.dyndnsUpdate}
      ''}
      ${optionalString (
        cfg.domains.${domainName}.ad.extraConfig != null
      ) ''${cfg.domains.${domainName}.ad.extraConfig}''}

      # LDAP Settings
      ldap_id_mapping = ${boolToString cfg.domains.${domainName}.ldap.idMapping}
      ${optionalString (cfg.domains.${domainName}.ldap.schema != null)
        "ldap_schema = ${cfg.domains.${domainName}.ldap.schema}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.tlsReqcert != null)
        "ldap_tls_reqcert = ${cfg.domains.${domainName}.ldap.tlsReqcert}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.tlsCaCert != null)
        "ldap_tls_cacert = ${cfg.domains.${domainName}.ldap.tlsCaCert}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.uri != [ ])
        "ldap_uri = ${lib.concatStringsSep "," cfg.domains.${domainName}.ldap.uri}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.baseDn != null)
        "ldap_search_base = ${cfg.domains.${domainName}.ldap.baseDn}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.defaultBindDn != null)
        "ldap_default_bind_dn = ${cfg.domains.${domainName}.ldap.defaultBindDn}"
      }
      ${optionalString (cfg.domains.${domainName}.ldap.defaultAuthtok != null)
        "ldap_default_authtok = ${cfg.domains.${domainName}.ldap.defaultAuthtok}"
      }
      ${optionalString (
        cfg.domains.${domainName}.ldap.extraConfig != null
      ) ''${cfg.domains.${domainName}.ldap.extraConfig}''}

      ${optionalString (cfg.domains.${domainName}.accessProvider == "simple") ''
        # Simple Access Control
        simple_allow_users = ${lib.concatStringsSep "," cfg.domains.${domainName}.simple.allowUsers}
        simple_deny_users = ${lib.concatStringsSep "," cfg.domains.${domainName}.simple.denyUsers}
        simple_allow_groups = ${lib.concatStringsSep "," cfg.domains.${domainName}.simple.allowGroups}
        simple_deny_groups = ${lib.concatStringsSep "," cfg.domains.${domainName}.simple.denyGroups}
      ''}
    '') (lib.attrNames cfg.domains)}
  '';

  # Filter for domains with DNS providers
  dnsDomains = lib.filter (name: cfg.domains.${name}.dnsProvider != null) (lib.attrNames cfg.domains);

in
{
  options.ghaf.services.sssd = {
    enable = mkEnableOption "Enable client-side SSSD.";

    debugLevel = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "SSSD debug level. Higher values are more verbose.";
    };

    multiUser = mkOption {
      type = types.bool;
      default = false;
      description = "Enable support to enroll multiple users on the device. This is currently unsupported.";
      readOnly = true;
    };

    services = mkOption {
      type = types.listOf types.str;
      default = [
        "nss"
        "pam"
        # "autofs" - TODO
        # "sudo" - TODO
        # "pac" - not supported
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
      type = types.attrsOf (
        types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              default = "Default SSSD domain";
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
              default = "ad";
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

            autofsProvider = mkOption {
              type = types.enum [
                "ldap"
                "ipa"
                "ad"
                "none"
              ];
              default = "none";
              description = "Autofs provider for the domain.";
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

            cacheCredentials = mkOption {
              type = types.bool;
              default = true;
              description = "Cache user credentials for offline logins.";
            };

            entryCacheTimeout = mkOption {
              type = types.int;
              default = 5400;
              description = "The number of seconds SSSD will keep a cache entry before it is expired.";
            };

            minId = mkOption {
              type = types.int;
              default = 1;
              description = "Minimum UID and GID for this domain.";
            };

            maxId = mkOption {
              type = types.int;
              default = 0;
              description = "Maximum UID and GID for this domain.";
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
                description = "List of Active Directory domain controllers. If empty, SSSD will use DNS for discovery.";
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
              defaultBindDn = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "The default Bind DN to use for LDAP queries.";
              };
              defaultAuthtok = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "The password for the default Bind DN. WARNING: Storing this in your configuration is insecure.";
              };
              tlsReqcert = mkOption {
                type = types.nullOr (
                  types.enum [
                    "never"
                    "allow"
                    "try"
                    "demand"
                    "hard"
                  ]
                );
                default = null;
                example = "allow";
                description = "TLS certificate checking policy.";
              };
              tlsCaCert = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "/etc/ssl/certs/ca-certificates.crt";
                description = "Path to the CA certificate for TLS.";
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
                type = types.str;
                default = "";
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

            simple = {
              allowUsers = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Simple user allow list.";
              };
              denyUsers = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Simple user deny list.";
              };
              allowGroups = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Simple group allow list.";
              };
              denyGroups = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Simple group deny list.";
              };
            };
          };
        }
      );
      default = { };
      description = "SSSD domain configurations.";
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
      kcm = lib.any (d: (d.authProvider == "krb5" || d.authProvider == "ad")) (
        lib.attrValues cfg.domains
      );
      config = sssdConfig;
    };

    # SSSD service dependencies
    systemd.services.sssd = {
      serviceConfig = {
        before = [
          "greetd.service"
          "cosmic-greeter.service"
        ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };

    ghaf = optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
      # SSSD persistent storage
      storagevm = {
        directories = [
          {
            directory = "/var/lib/sss";
            user = "root";
            group = "root";
            mode = "0755"; # TODO check minimal permissions (nss)
          }
        ];
        files = [
          {
            file = "/etc/krb5.keytab";
            user = "root";
            group = "root";
            mode = "0600";
          }
        ];
      };
      # Watch critical files
      security.audit.extraRules = [
        "-w /var/lib/sss -p wa -k sssd"
        "-w /etc/krb5.keytab -p wa -k krb5"
      ];
    };

    # TODO Add group autojoin in PAM stack with SSSD, or remove groups
    # Ghaf AD user group for access control
    # users.groups.ghaf-users = {
    #   name = "ghaf-users";
    #   gid = 700;
    # };
    # Automatic group setup (requires membership in ghaf-users group)
    # environment.etc."security/group.conf".text = ''
    #   *;*;%ghaf-users;Al0000-2400;users,video,audio
    # '';

    # Enable SSSD PAM services
    security.pam.services = optionalAttrs (cfg.pam.displayManagerService != null) {
      "${cfg.pam.displayManagerService}" = {
        sssdStrictAccess = true;
        makeHomeDir = false;
      };
    };

    # TODO Support autofs+nfs for AD users
    # services.autofs =
    #   let
    #     autoHome = pkgs.writeText "auto.home" ''
    #       * -fstype=nfs,rw example.com:/home/&
    #     '';
    #   in
    #   {
    #     enable = true;
    #     autoMaster = ''
    #       /home ${autoHome}
    #     '';
    #   };

    # Setup DNS for domains with DNS providers
    networking.hosts = foldr recursiveUpdate { } (
      map (name: {
        "${cfg.domains.${name}.dnsProvider.ipAddress}" = [ "${cfg.domains.${name}.dnsProvider.name}" ];
      }) dnsDomains
    );
    systemd.network.networks."10-${interfaceName}".dns = map (
      name: cfg.domains.${name}.dnsProvider.ipAddress
    ) dnsDomains;
  };
}
