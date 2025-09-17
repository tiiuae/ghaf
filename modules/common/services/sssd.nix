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
    any
    attrNames
    attrValues
    boolToString
    filter
    foldr
    head
    concatMapStrings
    concatStringsSep
    mkEnableOption
    mkIf
    mkOption
    optionalString
    optionalAttrs
    recursiveUpdate
    types
    ;
  inherit (config.ghaf.networking.hosts.${config.networking.hostName}) interfaceName;

  # TODO Support TPM sealing for ldap bind pwd and keytabs once available
  # TODO Tune local_auth_policy and authentication policy, check [prompting/...] support
  # TODO Potentially integrate FIDO2 support
  # TODO Parametrize or dynamically fetch user home size (default: 10G)
  # TODO AD join will use GUI-VM as hostname, add dynamic gui-vm hostname support?
  # TODO Add more AD controls such as ad_gpo_map_interactive
  # TODO Add sudo provider / AD sudo support?
  # TODO Test interactive setup with users from multiple domains, only single AD setup has been tested
  # TODO Fetch password change policy from AD, or static 'homectl --password-change-now=true'
  # TODO Add UI password change: add cosmic-greeter support or switch login manager
  # TODO Remove user enumeration, currently greetd/cosmic-greeter needs this to list users
  # TODO Potentially support other authentication than GSSAPI in user setup
  # TODO Add functionality to setup script to add users from multiple domains (also requires working
  #      multi-user setup)
  # TODO Extend with WiFi setup - requires internet access, so currently have to use a USB ethernet dongle

  setupLockFile = "/var/lib/nixos/user.lock";

  # SSSD configuration template
  sssdConfig = ''
    [sssd]
    config_file_version = 2
    services = ${concatStringsSep ", " cfg.services}
    domains = ${concatStringsSep ", " (attrNames cfg.domains)}
    ${optionalString (cfg.debugLevel != null) "debug_level = ${toString cfg.debugLevel}"}
    core_dumpable = false

    [nss]
    filter_users = ${concatMapStrings (u: u + " ") (lib.attrNames config.users.users)}
    filter_groups = ${concatMapStrings (g: g + " ") (lib.attrNames config.users.groups)}
    reconnection_retries = 3
    ${optionalString (cfg.nss.homedirTemplate != null) "override_homedir = ${cfg.nss.homedirTemplate}"}
    ${optionalString (cfg.nss.shellOverride != null) "override_shell = ${cfg.nss.shellOverride}"}
    ${optionalString (cfg.nss.defaultShell != null) "default_shell = ${cfg.nss.defaultShell}"}
    entry_cache_nowait_percentage = ${toString cfg.entryCacheNowaitPercentage}

    [pam]
    reconnection_retries = 3
    offline_credentials_expiration = ${toString cfg.pam.offlineCredentialsExpiration}
    offline_failed_login_attempts = ${toString cfg.pam.offlineFailedLoginAttempts}
    offline_failed_login_delay = ${toString cfg.pam.offlineFailedLoginDelay}

    ${concatMapStrings (domainName: ''
      [domain/${domainName}]
      description = "${cfg.domains.${domainName}.description}"
      cache_credentials = ${boolToString cfg.domains.${domainName}.cacheCredentials}
      entry_cache_timeout = ${toString cfg.domains.${domainName}.entryCacheTimeout}

      # TODO Remove this, currently greetd needs this for user enumeration
      enumerate = true

      # Kerberos Settings
      krb5_store_password_if_offline = true
      ${optionalString (cfg.domains.${domainName}.krb5.realm != "")
        "krb5_realm = ${cfg.domains.${domainName}.krb5.realm}"
      }
      ${optionalString (cfg.domains.${domainName}.krb5.server != [ ])
        "krb5_server = ${concatStringsSep "," cfg.domains.${domainName}.krb5.server}"
      }
      ${optionalString (cfg.domains.${domainName}.krb5.kpasswd != [ ])
        "krb5_kpasswd = ${concatStringsSep "," cfg.domains.${domainName}.krb5.kpasswd}"
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
        ad_server = ${concatStringsSep "," cfg.domains.${domainName}.ad.controllers}
        ad_gpo_access_control = ${cfg.domains.${domainName}.ad.gpoAccessControl}
        dyndns_update = ${boolToString cfg.domains.${domainName}.ad.dyndnsUpdate}
      ''}

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
        "ldap_uri = ${concatStringsSep "," cfg.domains.${domainName}.ldap.uri}"
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
        simple_allow_users = ${concatStringsSep "," cfg.domains.${domainName}.simple.allowUsers}
        simple_deny_users = ${concatStringsSep "," cfg.domains.${domainName}.simple.denyUsers}
        simple_allow_groups = ${concatStringsSep "," cfg.domains.${domainName}.simple.allowGroups}
        simple_deny_groups = ${concatStringsSep "," cfg.domains.${domainName}.simple.denyGroups}
      ''}
    '') (attrNames cfg.domains)}
  '';

  # Filter for domains with DNS providers
  dnsDomains = filter (name: cfg.domains.${name}.dnsProvider != null) (attrNames cfg.domains);

in
{
  options.ghaf.services.sssd = {
    enable = mkEnableOption "Enable client-side SSSD.";

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
    };

  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.domains != { };
        message = "At least one domain must be defined when using the SSSD module.";
      }
    ];

    # Enable homed service
    services.homed.enable = true;

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
      kcm = any (d: (d.authProvider == "krb5" || d.authProvider == "ad")) (attrValues cfg.domains);
      config = sssdConfig;
    };
    systemd.services.sssd = {
      serviceConfig = {
        before = [ "display-manager.service" ];
        after = [ "local-fs.target" ];
      };
      unitConfig.ConditionPathExists = "${setupLockFile}";
    };

    ghaf = {
      # Enable systemd homed support
      systemd.withHomed = true;
    }
    // lib.optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
      # SSSD persistent storage
      storagevm = {
        directories = [
          {
            directory = "/var/lib/sss";
            user = "root";
            group = "root";
            # TODO check minimal permissions (nss)
            mode = "0755";
          }
          {
            directory = "/var/lib/systemd/home";
            user = "root";
            group = "root";
            mode = "0600";
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

    # Enable SSSD PAM services
    security.pam.services = optionalAttrs (cfg.pam.displayManagerService != null) {
      "${cfg.pam.displayManagerService}" = {
        sssdStrictAccess = true;
      };
    };

    # Setup DNS for domains with DNS providers
    networking.hosts = foldr recursiveUpdate { } (
      map (name: {
        "${cfg.domains.${name}.dnsProvider.ipAddress}" = [ "${cfg.domains.${name}.dnsProvider.name}" ];
      }) dnsDomains
    );
    systemd.network.networks."10-${interfaceName}".dns = map (
      name: cfg.domains.${name}.dnsProvider.ipAddress
    ) dnsDomains;

    # Interactive setup service to join domains
    systemd.services.sssd-interactive-setup =
      let
        # Nix wrapper to populate domain data
        domainData = concatStringsSep "\n" (
          map (
            name:
            ''
              domain_names+=("${name}")
              providers["${name}"]="${cfg.domains.${name}.idProvider}"
              min_ids["${name}"]="${toString cfg.domains.${name}.minId}"
              max_ids["${name}"]="${toString cfg.domains.${name}.maxId}"
              ldap_uris["${name}"]="${head cfg.domains.${name}.ldap.uri}"
            ''
            + optionalString (cfg.domains.${name}.ad != null) ''
              ad_domains["${name}"]="${cfg.domains.${name}.ad.domain}"
            ''
          ) (attrNames cfg.domains)
        );

        setupScript = pkgs.writeShellApplication {
          name = "sssd-interactive-setup";
          runtimeInputs = [
            pkgs.systemd
            pkgs.coreutils
            pkgs.umount
            pkgs.gawk
            pkgs.gnused
            pkgs.sssd
            pkgs.adcli
            pkgs.oddjob
            pkgs.brightnessctl
            pkgs.ncurses
            pkgs.bash
            pkgs.openldap
            pkgs.krb5
            pkgs.hostname
            pkgs.ldap-query
            pkgs.iputils
          ];
          text = ''
            set +euo pipefail
            trap ''' INT
            brightnessctl set 100%

            SETUP_LOCK="${setupLockFile}"
            KERBEROS_KEYTAB="/etc/krb5.keytab"

            acquire_kerberos_ticket() {
              if [ ! -r "$KERBEROS_KEYTAB" ]; then
                  echo "Error: Kerberos keytab not found or not readable at '$KERBEROS_KEYTAB'."
                  echo "Please ensure the path is correct and the script has permission to read it (e.g., run as root)."
                  sleep 3
                  exit 1
              fi

              local AD_REALM
              local MACHINE_HOSTNAME
              local KERBEROS_PRINCIPAL

              AD_REALM=$(echo "$1" | tr '[:lower:]' '[:upper:]')
              MACHINE_HOSTNAME=$(hostname -f | tr '[:lower:]' '[:upper:]')
              KERBEROS_PRINCIPAL="$MACHINE_HOSTNAME\$@$AD_REALM"

              if ! kinit -kt "$KERBEROS_KEYTAB" "$KERBEROS_PRINCIPAL"; then
                  echo "Error: kinit failed to acquire a Kerberos ticket."
                  echo "Check the principal name, keytab content, and network connection to the KDC."
                  exit 1
              fi
              echo "Kerberos ticket acquired successfully."
            }

            get_base_dn() {
              local domain="$1"
              local base_dn=""
              local IFS='.'
              # shellcheck disable=SC2206 # We want word splitting here
              local domain_parts=($domain)
              for part in "''${domain_parts[@]}"; do
                if [ -z "$base_dn" ]; then
                  base_dn="dc=$part"
                else
                  base_dn="$base_dn,dc=$part"
                fi
              done
              echo "$base_dn"
            }

            clear
            echo -e "\e[1;32;1m======================================================\e[0m"
            echo -e "\e[1;32;1m Welcome to Ghaf \e[0m"
            echo -e "\e[1;32;1m======================================================\e[0m"
            echo

            if [ "$EUID" -ne 0 ]; then
              echo "Error: This script must be run as root."
              sleep 3
              exit 1
            fi

            # Populate domain data
            declare -A providers
            declare -A ad_domains
            declare -A min_ids
            declare -A max_ids
            declare -A ldap_uris
            declare -a domain_names
            ${domainData}

            # Wait for network to be online
            echo -n "Waiting for internet connection..."
            while ! ping -c 1 8.8.8.8 &>/dev/null; do
              sleep 1
            done
            echo " connected."

            while true; do

              echo
              echo "======================================================"
              echo " SSSD Interactive Setup"
              echo "======================================================"
              echo
              echo "Available domains:"
              for domain in "''${domain_names[@]}"; do
                echo "  - ''$domain (provider: ''${providers[$domain]})"
              done
              echo

              # Interactive Domain Selection
              DOMAIN_NAME=""
              while true; do
                read -r -p "Please type the name of the domain to configure: " selected_domain
                for domain in "''${domain_names[@]}"; do
                  if [[ "$domain" == "$selected_domain" ]]; then
                    DOMAIN_NAME="$selected_domain"
                    break
                  fi
                done

                if [ -n "$DOMAIN_NAME" ]; then
                  break
                else
                  echo "Invalid domain name. Please try again."
                fi
              done

              PROVIDER="''${providers[$DOMAIN_NAME]}"

              echo
              echo "Configuring domain: ''$DOMAIN_NAME"
              echo "Using provider: ''$PROVIDER"
              echo

              # Provider specific logic
              AD_DOMAIN="''${ad_domains[$DOMAIN_NAME]}"
              echo "Preparing to join Active Directory domain: ''$AD_DOMAIN"
              read -r -p "Enter an AD user with permissions to join the domain (e.g., Administrator): " AD_USER
              echo
              echo

              # adcli does not accept the pre-created keytab file, so
              # we remove it to force re-creation
              if [ -e "$KERBEROS_KEYTAB" ]; then
                umount "$KERBEROS_KEYTAB"
                rm "$KERBEROS_KEYTAB"
              fi

              echo "Attempting to join the domain..."
              if ! adcli join --user="$AD_USER" "$AD_DOMAIN" --verbose; then
                echo "### ERROR: Failed to join the Active Directory domain."
                echo "Restarting the setup..."
                sleep 3
                continue
              fi
              echo "Successfully joined the domain."

              # Copy the newly created keytab to the storage
              rm "${config.ghaf.storagevm.mountPath}$KERBEROS_KEYTAB"
              cp "$KERBEROS_KEYTAB" "${config.ghaf.storagevm.mountPath}$KERBEROS_KEYTAB"

              read -r -p "Do you want to finish the SSSD setup? [Y/n] " response
              case "$response" in
              [nN][oO] | [nN])
                continue
                ;;
              *)
                break
                ;;
              esac

            done

            echo
            echo "SSSD setup completed."
            echo

            USER_SETUP_COMPLETE=false
            until $USER_SETUP_COMPLETE; do

              echo
              echo "======================================================"
              echo " AD USER Interactive Setup"
              echo "======================================================"
              echo

              MIN_UID="''${min_ids[$DOMAIN_NAME]}"
              MAX_UID="''${max_ids[$DOMAIN_NAME]}"
              if [ "$MAX_UID" -eq 0 ]; then
                MAX_UID=999999
              fi
              LDAP_SERVER="''${ldap_uris["$DOMAIN_NAME"]}"
              BASE_DN=$(get_base_dn "$DOMAIN_NAME")

              echo "Base DN: $BASE_DN"
              echo "LDAP Server: $LDAP_SERVER"
              echo "UID Range: $MIN_UID - $MAX_UID"

              # Query LDAP for appropriate AD Users and fetch infos
              acquire_kerberos_ticket "$AD_DOMAIN"
              echo
              ${lib.getExe pkgs.ldap-query} \
                --server "$LDAP_SERVER" \
                --base-dn "$BASE_DN" \
                --min-uid "$MIN_UID" \
                --max-uid "$MAX_UID" | \
            while IFS='|' read -r name display_name uid gid; do
              printf "Username:      %s\n" "$name"
              printf "Display Name:  %s\n" "$display_name"
              printf "UID:           %s\n" "$uid"
              printf "GID:           %s\n" "$gid"

              # Select whether to create a user home
              read -r -p "Do you want to enroll this user? [y/N] " create_home < /dev/tty
              case "$create_home" in
                [Yy]* )
                  if ! homectl create "$name" \
                  --realm="$AD_DOMAIN" \
                  --real-name="$display_name" \
                  --skel=/etc/skel \
                  --storage=luks \
                  --luks-pbkdf-type=argon2id \
                  --fs-type=btrfs \
                  --enforce-password-policy=true \
                  --recovery-key=true \
                  --drop-caches=true \
                  --nosuid=true \
                  --noexec=true \
                  --nodev=true \
                  --disk-size=10000M \
                  --shell=/run/current-system/sw/bin/bash \
                  --uid="$uid" \
                  --member-of=users${
                    optionalString (
                      config.ghaf.users.homedUser.extraGroups != [ ]
                    ) ",${concatStringsSep "," config.ghaf.users.homedUser.extraGroups}"
                  } < /dev/tty; then
                    echo "An error occurred while creating the user account. Please try again." >&2
                  fi
                  ;;
                * )
                  echo "Skipping user enrollment for '$name'."
                  ;;
              esac
            done

              # User to confirm the setup
              echo
              homectl
              echo
              read -r -p "Do you want to continue with this configuration? [Y/n] " response

              case "$response" in
              [nN][oO] | [nN])
                USER_LIST=$(homectl list | tail -n +2 | awk '{print $1}')
                for USER in $USER_LIST; do
                  if ! homectl remove "$USER"; then
                    echo "Error: Failed to remove '$USER'."
                  fi
                done
                rm -r /var/lib/systemd/home/*
                ;;
              *)
                echo "Setup completed. Starting graphical session..."
                USER_SETUP_COMPLETE=true
                ;;
              esac
            done

            # Create lock file to run the setup once
            install /dev/null -m 000 "$SETUP_LOCK"
          '';
        };
      in
      {
        description = "SSSD Interactive Domain Join";
        wantedBy = [ "multi-user.target" ];
        before = [
          "sssd.service"
          "display-manager.service"
        ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${setupScript}/bin/sssd-interactive-setup";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = true;
          TTYVHangup = true;
          Restart = "on-failure";
          RestartSec = "5s";
        };
        unitConfig.ConditionPathExists = "!${setupLockFile}";
      };
  };
}
