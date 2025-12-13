# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Demo deployment profile
#
# This profile configures Ghaf for demonstrations, conferences, and
# customer presentations. It disables telemetry, uses local-only
# logging, and includes demo-friendly defaults.
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.deployments.profiles.demo;
in
{
  options.ghaf.reference.deployments.profiles.demo = {
    enable = lib.mkEnableOption "Demo deployment profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf.reference.deployments = {
      # Logging - disabled for demos (no external connectivity needed)
      logging = {
        serverEndpoint = lib.mkDefault "";
      };

      # Business VM - open configuration for demos
      businessVm = {
        proxyPacUrl = lib.mkDefault "";
      };

      # Proxy server - enabled but with relaxed settings for demos
      proxy = {
        enable = lib.mkDefault true;
      };

      # GlobalProtect VPN - disabled for demos (no corporate network)
      globalProtect = {
        enable = lib.mkDefault false;
        serverAddress = lib.mkDefault "";
      };

      # Gala - disabled for demos (requires specific infrastructure)
      gala = {
        enable = lib.mkDefault false;
        serverUrl = lib.mkDefault "";
      };

      # Development - no SSH access or debug tools for demos
      development = {
        enableSshAccess = lib.mkDefault false;
        enableDebugTools = lib.mkDefault false;
        authorizedSshKeys = lib.mkDefault [ ];
      };

      # Network settings - use public DNS for portability
      networking = {
        dnsServers = lib.mkDefault [
          "1.1.1.1"
          "8.8.8.8"
        ];
        ntpServers = lib.mkDefault [ "pool.ntp.org" ];
      };

      # WireGuard VPN - disabled for demos (simpler setup)
      wireguard = {
        enable = lib.mkDefault false;
        enabledVms = lib.mkDefault [ ];
      };

      # Identity - local only for demos
      identity = {
        provider = lib.mkDefault "local";
      };

      # Security settings - disabled for ease of demo
      security = {
        auditEnabled = lib.mkDefault false;
        encryptionEnabled = lib.mkDefault false;
      };

      # Feature flags - minimal for demos
      features = {
        enableTelemetry = lib.mkDefault false;
        enableRemoteManagement = lib.mkDefault false;
        enableDebugTools = lib.mkDefault false;
      };

      # Branding - generic for demos
      branding = {
        organizationName = lib.mkDefault "Ghaf Platform Demo";
      };
    };
  };
}
