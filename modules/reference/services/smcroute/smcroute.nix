# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.smcroute;
in
{
  _file = ./smcroute.nix;

  options.services.smcroute = {
    enable = lib.mkEnableOption "smcroute";
    confFile = lib.mkOption {
      type = lib.types.path;
      example = "/var/lib/smcroute/smcroute.conf";
      description = ''
        Ignore all other smcroute options and load configuration from this file.
      '';
    };

    bindingNic = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "";
      description = ''
        Binding NIC
      '';
    };

    rules = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        https://github.com/troglobit/smcroute?tab=readme-ov-file#usage
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.bindingNic != "";
        message = "Binding Nic must be set";
      }
    ];

    # https://github.com/troglobit/smcroute?tab=readme-ov-file#linux-requirements
    boot.kernelPatches = [
      {
        name = "multicast-routing-config";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          IP_MULTICAST = yes;
          IP_MROUTE = yes;
          IP_PIMSM_V1 = yes;
          IP_PIMSM_V2 = yes;
          IP_MROUTE_MULTIPLE_TABLES = yes; # For multiple routing tables
        };
      }
    ];

    services.smcroute.confFile = lib.mkDefault (
      pkgs.writeText "smcroute.conf" ''

        ${lib.concatStringsSep "\n" (lib.optionals (cfg.rules != null) [ cfg.rules ])}
      ''
    );

    systemd.services."smcroute" = {
      description = "Static Multicast Routing daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      preStart = ''
        # wait until ${cfg.bindingNic} has an ip
        sleep 5
        while [ -z "$ip" ]; do
         ip=$(${pkgs.nettools}/bin/ifconfig ${cfg.bindingNic} | ${pkgs.gawk}/bin/awk '/inet / {print $2}')
              [ -z "$ip" ] && ${pkgs.coreutils}/bin/sleep 1
        done
        exit 0
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.smcroute}/sbin/smcrouted -n -s -f ${cfg.confFile}";
        User = "root";
        # Restart the service if it fails
        Restart = "on-failure";
        # Wait a second before restarting.
        RestartSec = "5s";
        ProtectHome = true;
        NoNewPrivileges = true;
        ProtectControlGroups = true;
        ProtectSystem = "full";
      };
    };

  };

}
