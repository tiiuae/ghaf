# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TII Internal deployment profile
#
# This profile configures Ghaf for internal TII testing and development.
# It includes internal logging endpoints, development features, and
# TII-specific network configuration.
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.deployments.profiles.tii-internal;
in
{
  options.ghaf.reference.deployments.profiles.tii-internal = {
    enable = lib.mkEnableOption "TII internal deployment profile";
  };

  config = lib.mkIf cfg.enable {
    ghaf.reference.deployments = {
      # Logging configuration for TII internal Loki instance
      logging = {
        serverEndpoint = lib.mkDefault "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
      };

      # Business VM configuration
      businessVm = {
        proxyPacUrl = lib.mkDefault "";
      };

      # Proxy server - use TII defaults
      proxy = {
        enable = lib.mkDefault true;
        microsoftEndpointsUrl = lib.mkDefault "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7";
        allowlistRepoUrl = lib.mkDefault "https://api.github.com/repos/tiiuae/ghaf-rt-config/contents/network/proxy/urls?ref=main";
      };

      # GlobalProtect VPN - enabled with TII server
      globalProtect = {
        enable = lib.mkDefault true;
        serverAddress = lib.mkDefault "151.253.154.18";
      };

      # Gala - enabled for TII internal
      gala = {
        enable = lib.mkDefault true;
        serverUrl = lib.mkDefault "https://gala.atrc.azure-atrc.androidinthecloud.net/#/login";
      };

      # Development - enable debug tools for internal testing
      development = {
        enableSshAccess = lib.mkDefault true;
        enableDebugTools = lib.mkDefault true;
        # TII developer SSH keys
        authorizedSshKeys = lib.mkDefault [
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo= brian@arcadia"
          "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo= brian@minerva"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILu6O3swRVWAjP7J8iYGT6st7NAa+o/XaemokmtKdpGa brian@builder"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKm9NtS/ZmrxQhY/pbRlX+9O1VaBEd8D9vojDtvS0Ru juliuskoskela@vega"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3w7NzqMuF+OAiIcYWyP9+J3kwvYMKQ+QeY9J8QjAXm shamma-alblooshi@tii.ae"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/iv9RWMN6D9zmEU85XkaU8fAWJreWkv3znan87uqTW humaid@tahr"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGOifxDCESZZouWLpoCWGXEYOVbMz53vrXTi9RQe4Bu5 hazaa@nixos"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwsW+YJw6ukhoWPEBLN93EFiGhN7H2VJn5yZcKId56W mb@mmm"
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCsjXKHCkpQT4LhWIdT0vDM/E/3tw/4KHTQcdJhyqPSH0FnwC8mfP2N9oHYFa2isw538kArd5ZMo5DD1ujL5dLk= joerg@turingmachine"
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLMlGNda7bilB0+3aMeJSFcB17auBPV0WhW60WlGZsQRF50Z/OgIHAA0/8HaxPmpIOLHv8JO3dCsj+OY1iS4FNo= joerg@turingmachine"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIstCgKDX1vVWI8MgdVwsEMhju6DQJubi3V0ziLcU/2h vunny.sodhi@unikie.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfyjcPGIRHEtXZgoF7wImA5gEY6ytIfkBeipz4lwnj6 Ganga.Ram@tii.ae"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEA7p7hHPvPT6uTU44Nb/p9/DT9mOi8mpqNllnpfawDE tanel@nixos"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwGPH/oOrD1g15uiPV4gBKGk7f8ZBSyMEaptKOVs3NG jaroslawkurowski@TII-JaroslawKurowski"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHu4r7nCQ6A26HsE4+wIupvXAfVQHgBGXv0+epCho2/m rodrigo.pino@tii.ae"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGll9sWYdGc2xi9oQ25TEcI1D3T4n8MMXoMT+lJdE/KC milla@nixos"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJSuGlmQ/iMu7JGL7L4jVT3d+o4MiOsuh0e1ZVkBUKq gayathri@tii.ae"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINlIpJ9Q1oW1KiFBa12N5K/ecGVeGSBbcD8M9ZjA0TYe kajus.naujokaitis@unikie.com"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPE/CgI8MXyHiiUyt7BXWjQG1pb25b4N3als/dKKPZyD samuli@nixos"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJpTkKsWyFQxWKwL22fghfJnLaOhUtZLlF9h2gdWcoJz everton.dematos@tii.ae"
          # For ghaf-installer automated testing:
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAolaKCuIUBQSBFGFZI1taNX+JTAr8edqUts7A6k2Kv7"
        ];
      };

      # Network settings for TII internal network
      networking = {
        dnsServers = lib.mkDefault [ ];
        ntpServers = lib.mkDefault [ "time.cloudflare.com" ];
      };

      # WireGuard VPN - enabled for internal deployments
      wireguard = {
        enable = lib.mkDefault true;
        enabledVms = lib.mkDefault [
          "business-vm"
          "chrome-vm"
        ];
      };

      # Identity - use local authentication for internal testing
      identity = {
        provider = lib.mkDefault "local";
      };

      # Security settings - relaxed for development
      security = {
        auditEnabled = lib.mkDefault false;
        encryptionEnabled = lib.mkDefault false;
      };

      # Feature flags for internal testing
      features = {
        enableTelemetry = lib.mkDefault true;
        enableRemoteManagement = lib.mkDefault false;
        enableDebugTools = lib.mkDefault true;
      };

      # Branding
      branding = {
        organizationName = lib.mkDefault "TII - Technology Innovation Institute";
      };
    };
  };
}
