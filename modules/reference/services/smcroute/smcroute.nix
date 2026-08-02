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
  # Seconds to wait for bindingNic to acquire an address before failing. Kept
  # below the default TimeoutStartSec (90s) so our diagnostic is what gets
  # logged, rather than systemd's generic "start-pre operation timed out".
  bindingNicTimeout = 60;
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
      # Wait for the binding NIC to get an address, but bounded. This loop used
      # to be unbounded, which turned "the interface never comes up" into a
      # permanent restart loop: systemd killed preStart at TimeoutStartSec (90s),
      # Restart=on-failure started it again, and round it went every ~95s
      # forever.
      preStart = ''
        deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString bindingNicTimeout} ))
        while :; do
          if [ -n "$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${cfg.bindingNic} scope global 2>/dev/null)" ]; then
            exit 0
          fi
          if [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ]; then
            echo "smcroute: '${cfg.bindingNic}' still has no global IPv4 address after ${toString bindingNicTimeout}s - giving up." >&2
            echo "smcroute: this NIC comes from ghaf.reference.services.chromecast.externalNic; it must name the interface that actually carries the LAN." >&2
            exit 1
          fi
          ${pkgs.coreutils}/bin/sleep 2
        done
      '';

      # Give up after a few attempts instead of restarting forever, so the unit
      # lands in "failed" where `systemctl --failed` and the log collector can
      # see it. Each attempt is bindingNicTimeout + RestartSec, so the interval
      # has to be comfortably larger than burst * that.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
      };

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
