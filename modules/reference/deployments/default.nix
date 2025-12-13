# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Deployment profiles provide deployment-specific configurations that can be
# applied on top of use-case profiles (like mvp-user-trial).
#
# This allows the same Ghaf build to be customized for different deployment
# environments (internal testing, customer deployments, demos, etc.) without
# modifying the core profile definitions.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [
    ./tii-internal.nix
    ./demo.nix
  ];

  options.ghaf.reference.deployments = {
    # Logging/Monitoring settings
    logging = {
      serverEndpoint = mkOption {
        type = types.str;
        default = "";
        description = ''
          The Grafana Loki endpoint URL where logs will be pushed.
          Example: "https://loki.example.com/loki/api/v1/push"
        '';
      };

      serverCaBundle = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Optional CA bundle for TLS verification when connecting to the
          logging server.
        '';
      };

      clientTlsCert = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "TLS client certificate for mutual TLS authentication.";
      };

      clientTlsKey = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "TLS client key for mutual TLS authentication.";
      };
    };

    # Business VM specific settings
    businessVm = {
      allowedUrlsRepo = mkOption {
        type = types.str;
        default = "";
        description = ''
          Git repository URL containing the allowed URLs list for business-vm.
          This repo is fetched at build time to configure URL filtering.
        '';
      };

      proxyPacUrl = mkOption {
        type = types.str;
        default = "";
        description = "Proxy PAC file URL for business-vm browser configuration.";
      };

      officeConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Microsoft 365 / Office configuration settings.";
      };
    };

    # Proxy server and URL allowlist settings
    proxy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable the proxy server for URL filtering.";
      };

      bindPort = mkOption {
        type = types.port;
        default = 3128;
        description = "Port for the proxy server to listen on.";
      };

      microsoftEndpointsUrl = mkOption {
        type = types.str;
        default = "";
        description = "Microsoft 365 endpoints API URL for allowlist generation.";
      };

      allowlistRepoUrl = mkOption {
        type = types.str;
        default = "";
        description = "GitHub API URL for fetching additional allowed URLs.";
      };

      allowlistRefreshInterval = mkOption {
        type = types.str;
        default = "hourly";
        description = "How often to refresh the URL allowlist (systemd calendar format).";
      };
    };

    # GlobalProtect VPN settings
    globalProtect = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GlobalProtect VPN client in business-vm.";
      };

      serverAddress = mkOption {
        type = types.str;
        default = "151.253.154.18";
        description = "GlobalProtect VPN server IP address or hostname.";
      };

      portalAddress = mkOption {
        type = types.str;
        default = "";
        description = "GlobalProtect portal address (if different from server).";
      };
    };

    # Gala (Android-in-Cloud) settings
    gala = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Gala (Android-in-Cloud) application.";
      };

      serverUrl = mkOption {
        type = types.str;
        default = "https://gala.atrc.azure-atrc.androidinthecloud.net/#/login";
        description = "Gala server URL for Android-in-Cloud access.";
      };
    };

    # Development and SSH access settings
    development = {
      authorizedSshKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of SSH public keys authorized for this deployment.
          These keys will be added to admin user's authorized_keys.
        '';
        example = [
          "ssh-ed25519 AAAAC3... user@host"
        ];
      };

      enableSshAccess = mkOption {
        type = types.bool;
        default = true;
        description = "Enable SSH access in this deployment.";
      };

      enableDebugTools = mkOption {
        type = types.bool;
        default = false;
        description = "Include debugging tools (tcpdump, strace, etc.) in the deployment.";
      };
    };

    # User account settings
    users = {
      adminPassword = mkOption {
        type = types.str;
        default = "ghaf";
        description = ''
          Initial password for the admin account.
          For production deployments, use adminHashedPassword instead.
        '';
      };

      adminHashedPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Hashed password for the admin account.
          Generate with: mkpasswd -m yescrypt
          If set, this takes precedence over adminPassword.
        '';
        example = "$y$j9T$...";
      };
    };

    # Network settings
    networking = {
      vpnEndpoint = mkOption {
        type = types.str;
        default = "";
        description = "VPN server endpoint for the deployment.";
      };

      vpnConfigFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "WireGuard or OpenVPN configuration file.";
      };

      dnsServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Custom DNS servers for this deployment.";
      };

      ntpServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Custom NTP servers for this deployment.";
      };

      httpProxy = mkOption {
        type = types.str;
        default = "";
        description = "HTTP proxy URL for outbound connections.";
      };

      httpsProxy = mkOption {
        type = types.str;
        default = "";
        description = "HTTPS proxy URL for outbound connections.";
      };

      noProxy = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of hosts/domains to exclude from proxy.";
      };
    };

    # WireGuard VPN settings
    wireguard = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable WireGuard GUI in this deployment.";
      };

      enabledVms = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of VM names where WireGuard GUI should be enabled.
          Example: [ "business-vm" "chrome-vm" ]
        '';
      };

      preConfiguredPeers = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Friendly name for this WireGuard peer/connection.";
              };
              endpoint = mkOption {
                type = types.str;
                description = "WireGuard server endpoint (host:port).";
              };
              publicKey = mkOption {
                type = types.str;
                description = "Server's WireGuard public key.";
              };
              allowedIPs = mkOption {
                type = types.listOf types.str;
                default = [ "0.0.0.0/0" ];
                description = "Allowed IPs for this peer.";
              };
              persistentKeepalive = mkOption {
                type = types.int;
                default = 25;
                description = "Persistent keepalive interval in seconds.";
              };
            };
          }
        );
        default = [ ];
        description = "Pre-configured WireGuard peers for this deployment.";
      };
    };

    # Active Directory / Identity Provider settings
    identity = {
      provider = mkOption {
        type = types.enum [
          "none"
          "azure-ad"
          "ldap"
          "local"
        ];
        default = "none";
        description = "Identity provider for user authentication.";
      };

      azure = {
        tenantId = mkOption {
          type = types.str;
          default = "";
          description = "Azure AD tenant ID for authentication.";
        };

        clientId = mkOption {
          type = types.str;
          default = "";
          description = "Azure AD application (client) ID.";
        };

        domain = mkOption {
          type = types.str;
          default = "";
          description = "Azure AD domain (e.g., contoso.onmicrosoft.com).";
        };
      };

      ldap = {
        serverUri = mkOption {
          type = types.str;
          default = "";
          description = "LDAP server URI (e.g., ldaps://ldap.example.com).";
        };

        baseDn = mkOption {
          type = types.str;
          default = "";
          description = "LDAP base DN for user searches.";
        };

        bindDn = mkOption {
          type = types.str;
          default = "";
          description = "LDAP bind DN for authentication.";
        };

        userSearchFilter = mkOption {
          type = types.str;
          default = "(uid=%s)";
          description = "LDAP filter for user searches.";
        };
      };
    };

    # Security settings
    security = {
      auditEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Enable security auditing for this deployment.";
      };

      encryptionEnabled = mkOption {
        type = types.bool;
        default = false;
        description = "Enable disk encryption for this deployment.";
      };

      customCaCerts = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = "Additional CA certificates to trust in this deployment.";
      };
    };

    # Feature flags for deployment-specific behavior
    features = {
      enableTelemetry = mkOption {
        type = types.bool;
        default = true;
        description = "Enable telemetry/metrics collection.";
      };

      enableRemoteManagement = mkOption {
        type = types.bool;
        default = false;
        description = "Enable remote management capabilities.";
      };

      enableDebugTools = mkOption {
        type = types.bool;
        default = false;
        description = "Include debugging tools in the deployment.";
      };
    };

    # Branding/customization
    branding = {
      organizationName = mkOption {
        type = types.str;
        default = "";
        description = "Organization name for branding purposes.";
      };

      wallpaper = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Custom wallpaper for the deployment.";
      };

      bootLogo = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Custom boot logo for the deployment.";
      };
    };
  };
}
