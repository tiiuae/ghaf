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

  # A *template*; the real config renders next to it in RuntimeDirectory.
  confTemplate = pkgs.writeText "smcroute.conf.in" ''
    ${lib.concatStringsSep "\n" (lib.optionals (cfg.rules.perUplink != null) [ cfg.rules.perUplink ])}
  '';
  confTemplateOnce = pkgs.writeText "smcroute-once.conf.in" ''
    ${lib.concatStringsSep "\n" (lib.optionals (cfg.rules.once != null) [ cfg.rules.once ])}
  '';
  runtimeConfFile = "/run/smcroute/smcroute.conf";

  # Renders the config once per resolved uplink, so a device with
  # several gets multicast routed on all of them, not just one.
  renderConf = pkgs.writeShellApplication {
    name = "smcroute-render-conf";
    runtimeInputs = [ pkgs.gnused ];
    text = ''
      uplink_ifaces=""
      # shellcheck disable=SC1091
      . ${cfg.stateFile}
      if [ -z "$uplink_ifaces" ]; then
        echo "smcroute: ${cfg.stateFile} names no uplink; refusing to route multicast on a guess." >&2
        exit 1
      fi
      : >${runtimeConfFile}
      sed -e "s|${cfg.placeholderAll}|$uplink_ifaces|g" ${confTemplateOnce} >>${runtimeConfFile}
      for iface in $uplink_ifaces; do
        sed -e "s|${cfg.placeholder}|$iface|g" ${confTemplate} >>${runtimeConfFile}
      done
      echo "smcroute: routing multicast on $uplink_ifaces"
    '';
  };
in
{
  _file = ./smcroute.nix;

  options.services.smcroute = {
    enable = lib.mkEnableOption "smcroute";

    rules = {
      perUplink = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        example = ''
          mgroup from @UPLINK@ group 239.255.255.250
          mroute from @UPLINK@ group 239.255.255.250 to ethint0
        '';
        description = ''
          smcroute rules repeated for each resolved uplink, with `placeholder`
          replaced by that uplink's interface name. See
          <https://github.com/troglobit/smcroute#usage>.
        '';
      };

      once = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        example = ''
          mroute from ethint0 group 239.255.255.250 to @UPLINKS@
        '';
        description = ''
          smcroute rules written once, with `placeholderAll` replaced by all
          resolved uplinks. Use it for rules that must list every uplink on one
          line; in `rules.perUplink` they would be repeated and smcrouted would
          reject the duplicate route.
        '';
      };
    };

    placeholder = lib.mkOption {
      type = lib.types.str;
      default = "@UPLINK@";
      description = ''
        Token in `rules.perUplink` replaced by the resolved uplink interface.
      '';
    };

    placeholderAll = lib.mkOption {
      type = lib.types.str;
      default = "@UPLINKS@";
      description = ''
        Token in `rules.once` replaced by every resolved uplink interface,
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
        File gating the unit. While it does not exist there is no uplink, and
        the unit is skipped rather than failed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.ghaf.networking.uplinkResolver.enable;
        message = "services.smcroute.enable requires ghaf.networking.uplinkResolver.enable";
      }
      {
        assertion = cfg.rules.perUplink == null || lib.hasInfix cfg.placeholder cfg.rules.perUplink;
        message = "services.smcroute.rules.perUplink must contain ${cfg.placeholder}";
      }
      {
        assertion = cfg.rules.once == null || lib.hasInfix cfg.placeholderAll cfg.rules.once;
        message = "services.smcroute.rules.once must contain ${cfg.placeholderAll}; rules without it belong in rules.perUplink";
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

      # No start rate limit: NetworkManager's dispatcher events can restart
      # this past the default limit when two uplinks change close together.
      unitConfig = {
        StartLimitIntervalSec = 0;
        # No uplink => skipped, visibly -- not failed, not silently succeeded.
        ConditionPathExists = cfg.readyFlag;
      };

      serviceConfig = {
        Type = "simple";
        ExecStartPre = lib.getExe renderConf;
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
