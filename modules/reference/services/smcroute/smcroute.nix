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

  # The store file is a *template* carrying the placeholders; the real config
  # is rendered next to it in the unit's RuntimeDirectory, which systemd
  # creates before ExecStartPre and removes on stop.
  confTemplate = pkgs.writeText "smcroute.conf.in" ''
    ${lib.concatStringsSep "\n" (lib.optionals (cfg.rules != null) [ cfg.rules ])}
  '';
  confTemplateOnce = pkgs.writeText "smcroute-once.conf.in" ''
    ${lib.concatStringsSep "\n" (lib.optionals (cfg.rulesOnce != null) [ cfg.rulesOnce ])}
  '';
  runtimeConfFile = "/run/smcroute/smcroute.conf";
in
{
  _file = ./smcroute.nix;

  options.services.smcroute = {
    enable = lib.mkEnableOption "smcroute";

    rules = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        https://github.com/troglobit/smcroute?tab=readme-ov-file#usage

        Rendered once per resolved uplink, with `placeholder` substituted for
        the interface being rendered. Put anything here that must be a
        *separate* directive per uplink (e.g. `mgroup from @UPLINK@ ...`, or
        an mroute whose source is the uplink). A directive that instead needs
        every uplink named on the same line (e.g. an mroute fanning out from
        the internal interface to all of them) belongs in `rulesOnce`
        instead -- repeating it here would redeclare the same route with a
        different destination each time, which smcrouted rejects.
      '';
    };

    rulesOnce = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Rendered exactly once, with `placeholderAll` substituted for every
        resolved uplink, space-separated -- for directives that must name all
        of them on one line, such as an mroute's `to` list. See `rules` for
        the per-uplink counterpart.
      '';
    };

    placeholder = lib.mkOption {
      type = lib.types.str;
      default = "@UPLINK@";
      description = ''
        Token in `rules` replaced by the resolved uplink interface.
      '';
    };

    placeholderAll = lib.mkOption {
      type = lib.types.str;
      default = "@UPLINKS@";
      description = ''
        Token in `rulesOnce` replaced by every resolved uplink interface,
        space-separated.
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

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # smcroute has no build-time fallback any more: it always renders its
        # config from the resolver's state file, so without the resolver
        # actually running, ConditionPathExists never sees a ready flag and
        # the unit sits silently skipped forever instead of failing loudly.
        assertion = config.ghaf.networking.uplinkResolver.enable;
        message = ''
          services.smcroute.enable requires ghaf.networking.uplinkResolver.enable
          -- smcroute always renders its config from the resolved uplink, and
          without the resolver it would never see a ready flag and would sit
          skipped forever instead of routing anything.
        '';
      }
      {
        assertion = cfg.rules == null || lib.hasInfix cfg.placeholder cfg.rules;
        message = ''
          services.smcroute.rules never mentions ${cfg.placeholder}, so the
          resolved uplink would be ignored and smcrouted would route
          multicast on the wrong interface -- silently, which is the exact
          failure this mechanism exists to prevent.
        '';
      }
      {
        assertion = cfg.rulesOnce == null || lib.hasInfix cfg.placeholderAll cfg.rulesOnce;
        message = ''
          services.smcroute.rulesOnce never mentions ${cfg.placeholderAll}.
          If a directive doesn't need the uplink list, it belongs in `rules`
          instead -- rulesOnce exists only for directives that must name
          every uplink on one line.
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

    systemd.services."smcroute" = {
      description = "Static Multicast Routing daemon";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "ghaf-uplink-resolver.service"
      ];
      requires = [ "network-online.target" ];

      # With the uplink resolved at runtime there is nothing left to wait
      # for: the resolver only publishes an interface once it holds the
      # default route, and ConditionPathExists below keeps this unit from
      # starting at all until at least one does. What remains is rendering
      # the config once per resolved uplink -- a device with several
      # simultaneous uplinks (Wi-Fi and a docked Ethernet, say) gets
      # multicast routed on all of them, not just one.
      preStart = ''
        # shellcheck disable=SC1090,SC1091
        . ${cfg.stateFile}
        if [ -z "''${uplink_ifaces:-}" ]; then
          echo "smcroute: ${cfg.stateFile} names no uplink; refusing to route multicast on a guess." >&2
          exit 1
        fi
        : >${runtimeConfFile}
        # rulesOnce first: directives naming every uplink on one line
        # (e.g. an mroute's `to` list), rendered exactly once.
        ${pkgs.gnused}/bin/sed -e "s|${cfg.placeholderAll}|$uplink_ifaces|g" \
          ${confTemplateOnce} >>${runtimeConfFile}
        # rules next: directives that are their own thing per uplink
        # (e.g. `mgroup from @UPLINK@ ...`), rendered once per uplink.
        for iface in $uplink_ifaces; do
          ${pkgs.gnused}/bin/sed -e "s|${cfg.placeholder}|$iface|g" \
            ${confTemplate} >>${runtimeConfFile}
        done
        echo "smcroute: routing multicast on $uplink_ifaces"
      '';

      # Kept from the bounded-wait fix this replaced. It should no longer be
      # reachable via a missing interface -- that is now a skip, not a retry
      # loop -- but a genuinely crashing smcrouted must still stop rather
      # than spin.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
        # No uplink => skipped, and visibly so. Not failed: an unplugged dock
        # is not a defect. Not silently succeeded either, which is what the
        # old unbounded wait effectively did.
        ConditionPathExists = cfg.readyFlag;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.smcroute}/sbin/smcrouted -n -s -f ${runtimeConfFile}";
        User = "root";
        # Restart the service if it fails
        Restart = "on-failure";
        # Wait a second before restarting.
        RestartSec = "5s";
        # Created before ExecStartPre and removed on stop, so a stale config can
        # never outlive the uplink it was generated for.
        RuntimeDirectory = "smcroute";
        ProtectHome = true;
        NoNewPrivileges = true;
        ProtectControlGroups = true;
        ProtectSystem = "full";
      };
    };
  };
}
