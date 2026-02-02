# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.givc;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    optionalString
    ;
  addressSubmodule = types.submodule {
    options = {
      name = mkOption {
        description = "Name of the IP range for parsing";
        type = types.str;
      };
      addr = mkOption {
        description = "IP address of admin server";
        type = types.str;
      };
      port = mkOption {
        description = "Port of admin server";
        type = types.str;
      };
      protocol = mkOption {
        description = "Protocol of admin server";
        type = types.enum [
          "tcp"
          "unix"
          "vsock"
        ];
      };
    };
  };
  inherit (config.ghaf.networking) hosts;
  # Only compute adminAddress when admin-vm exists to avoid evaluation errors
  # on targets that don't have admin-vm (like generic-x86)
  adminAddress =
    if hosts ? "admin-vm" then
      {
        name = "admin-vm";
        addr = hosts."admin-vm".ipv4;
        port = "9001";
        protocol = "tcp";
      }
    else
      {
        name = "admin-vm";
        addr = "192.168.100.10"; # Fallback - shouldn't be used if GIVC is disabled
        port = "9001";
        protocol = "tcp";
      };
  mitmEnabled =
    config.ghaf.virtualization.microvm.idsvm.enable
    && config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable;
  idsExtraArgs = optionalString mitmEnabled "--user-data-dir=/home/${config.ghaf.users.appUser.name}/.config/google-chrome/Default --test-type --ignore-certificate-errors-spki-list=Bq49YmAq1CG6FuBzp8nsyRXumW7Dmkp7QQ/F82azxGU=";
in
{
  options.ghaf.givc = {
    enable = mkEnableOption "Enable gRPC inter-vm communication";
    debug = mkEnableOption "Enable givc debug mode";
    enableTls = mkOption {
      description = "Enable TLS for gRPC communication globally, or disable for debugging.";
      type = types.bool;
      default = true;
    };
    idsExtraArgs = mkOption {
      description = "Extra arguments for applications when IDS/MITM is enabled.";
      type = types.str;
    };
    appPrefix = mkOption {
      description = "Common application path prefix.";
      type = types.str;
    };
    adminConfig = mkOption {
      description = "Admin server configuration.";
      type = types.submodule {
        options = {
          name = mkOption {
            description = "Host name of admin server";
            type = types.str;
          };
          addresses = mkOption {
            description = "Addresses of admin server";
            type = types.listOf addressSubmodule;
          };
        };
      };
    };
    cliArgs = mkOption {
      description = "Arguments for the givc-cli to contact the admin service.";
      type = types.str;
      default = "";
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.debug -> (!config.ghaf.logging.enable);
        message = "Do not enable givc debug and logging simultaneously, you may leak private information.";
      }
    ];

    # Generic givc configs
    ghaf.givc = {
      inherit idsExtraArgs;
      appPrefix = "/run/current-system/sw/bin";
      cliArgs = builtins.replaceStrings [ "\n" ] [ " " ] ''
        --name ${adminAddress.name}
        --addr ${adminAddress.addr}
        --port ${adminAddress.port}
        ${optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
        ${optionalString config.ghaf.givc.enableTls "--cert /run/givc/cert.pem"}
        ${optionalString config.ghaf.givc.enableTls "--key /run/givc/key.pem"}
        ${optionalString (!config.ghaf.givc.enableTls) "--notls"}
      '';
    };
    # Givc admin server configuration
    ghaf.givc.adminConfig = {
      inherit (adminAddress) name;
      addresses = [
        adminAddress
      ];
    };
  };
}
