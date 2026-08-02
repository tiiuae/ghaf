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

  # With uplink.enable the store file is a *template* carrying the placeholder;
  # the real config is rendered next to it in the unit's RuntimeDirectory, which
  # systemd creates before ExecStartPre and removes on stop.
  confTemplate = pkgs.writeText "smcroute.conf.in" ''
    ${lib.concatStringsSep "\n" (lib.optionals (cfg.rules != null) [ cfg.rules ])}
  '';
  runtimeConfFile = "/run/smcroute/smcroute.conf";
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

    uplink = {
      enable = lib.mkEnableOption ''
        taking the binding NIC from the runtime uplink resolver instead of
        `bindingNic`. `rules` must then use `placeholder` wherever the uplink
        interface appears; it is substituted when the config is generated at
        start
      '';

      placeholder = lib.mkOption {
        type = lib.types.str;
        default = "@UPLINK@";
        description = ''
          Token in `rules` replaced by the resolved uplink interface.
        '';
      };

      stateFile = lib.mkOption {
        type = lib.types.path;
        default = "/run/ghaf-uplink-state";
        description = "Where the uplink resolver publishes the current uplink.";
      };

      readyFlag = lib.mkOption {
        type = lib.types.path;
        default = "/run/ghaf-uplink-ready";
        description = ''
          Gate for the unit. Absent means there is no uplink, and the unit is
          skipped rather than failed.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uplink.enable || cfg.bindingNic != "";
        message = "Binding Nic must be set, or services.smcroute.uplink.enable used";
      }
      {
        assertion =
          !cfg.uplink.enable || cfg.rules == null || lib.hasInfix cfg.uplink.placeholder cfg.rules;
        message = ''
          services.smcroute.uplink.enable is set but the rules never mention
          ${cfg.uplink.placeholder}, so the resolved uplink would be ignored and
          smcrouted would route multicast on the wrong interface -- silently,
          which is the exact failure this mechanism exists to prevent.
        '';
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
      after = [
        "network-online.target"
      ]
      ++ lib.optional cfg.uplink.enable "ghaf-uplink-resolver.service";
      requires = [ "network-online.target" ];

      preStart =
        if cfg.uplink.enable then
          # With the uplink resolved at runtime there is nothing left to wait
          # for: the resolver only publishes an interface that holds the default
          # route, and ConditionPathExists below keeps this unit from starting
          # at all until it does. What remains is substituting that interface
          # into the config, which smcrouted reads from a file at startup.
          ''
            # shellcheck disable=SC1090
            . ${cfg.uplink.stateFile}
            if [ -z "''${uplink_iface:-}" ]; then
              echo "smcroute: ${cfg.uplink.stateFile} names no uplink; refusing to route multicast on a guess." >&2
              exit 1
            fi
            ${pkgs.gnused}/bin/sed -e "s|${cfg.uplink.placeholder}|$uplink_iface|g" \
              ${confTemplate} >${runtimeConfFile}
            echo "smcroute: routing multicast on $uplink_iface"
          ''
        else
          # Legacy path, for consumers still naming a build-time bindingNic.
          # Unchanged from the bounded-wait fix: the loop used to be unbounded,
          # which turned "the interface never comes up" into a permanent restart
          # loop that hid in "activating" while systemctl --failed stayed clean.
          ''
            deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString bindingNicTimeout} ))
            while :; do
              if [ -n "$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${cfg.bindingNic} scope global 2>/dev/null)" ]; then
                exit 0
              fi
              if [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ]; then
                echo "smcroute: '${cfg.bindingNic}' still has no global IPv4 address after ${toString bindingNicTimeout}s - giving up." >&2
                echo "smcroute: set services.smcroute.uplink.enable to resolve the interface at runtime instead." >&2
                exit 1
              fi
              ${pkgs.coreutils}/bin/sleep 2
            done
          '';

      # Kept from the bounded-wait fix. It should no longer be reachable via a
      # missing interface -- that is now a skip, not a retry loop -- but a
      # genuinely crashing smcrouted must still stop rather than spin.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
      }
      // lib.optionalAttrs cfg.uplink.enable {
        # No uplink => skipped, and visibly so. Not failed: an unplugged dock is
        # not a defect. Not silently succeeded either, which is what the old
        # unbounded wait effectively did.
        ConditionPathExists = cfg.uplink.readyFlag;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.smcroute}/sbin/smcrouted -n -s -f ${
          if cfg.uplink.enable then runtimeConfFile else cfg.confFile
        }";
        User = "root";
        # Restart the service if it fails
        Restart = "on-failure";
        # Wait a second before restarting.
        RestartSec = "5s";
        # Created before ExecStartPre and removed on stop, so a stale config can
        # never outlive the uplink it was generated for.
        RuntimeDirectory = lib.mkIf cfg.uplink.enable "smcroute";
        ProtectHome = true;
        NoNewPrivileges = true;
        ProtectControlGroups = true;
        ProtectSystem = "full";
      };
    };

  };

}
