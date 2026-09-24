# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Resolves which interface currently carries the LAN ("the uplink") and
# publishes it for other units to consume, replacing the build-time
# PCI-passthrough NIC guess that a runtime dock or USB dongle never matches.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  cfg = config.ghaf.networking.uplinkResolver;

  stateFile = "/run/ghaf-uplink-state";
  readyFlag = "/run/ghaf-uplink-ready";
  changedFlag = "/run/ghaf-uplink-changed";

  resolver = pkgs.writeShellApplication {
    name = "ghaf-resolve-uplink";
    runtimeInputs = with pkgs; [
      iproute2
      coreutils
      gawk
    ];
    text = ''
      # The uplink is the interface holding the default route. Resolves
      # *every* one held at once (e.g. Wi-Fi + docked Ethernet), not just the first.
      internal=${lib.escapeShellArg cfg.internalInterface}
      pinned=${lib.escapeShellArg cfg.forceInterface}

      # `dev` field position varies (a gateway-less route has no `via`), so
      # search for the `dev` token instead of assuming a fixed column.
      mapfile -t routed_list < <(ip route show default 2>/dev/null \
        | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); break}}')
      routed="''${routed_list[0]:-}"

      candidate_ok() {
        # ethint0 faces the guest VMs; claiming it as uplink would bridge
        # multicast straight back inwards.
        [ "$1" != "$internal" ] && [ -e "/sys/class/net/$1" ]
      }

      ifaces=()
      if [ -n "$pinned" ]; then
        # An explicit pin wins outright (see the disagreement warning below).
        candidate_ok "$pinned" && ifaces=("$pinned")
      else
        seen=""
        for i in "''${routed_list[@]}"; do
          candidate_ok "$i" || continue
          case " $seen " in
            *" $i "*) continue ;;
          esac
          seen="$seen $i"
          ifaces+=("$i")
        done
      fi

      uplink_ifaces="''${ifaces[*]}"

      if [ ''${#ifaces[@]} -eq 0 ]; then
        state=none
        if [ -z "$routed" ] && [ -z "$pinned" ]; then
          reason="no default route"
        elif [ "''${pinned:-$routed}" = "$internal" ]; then
          reason="default route is on the internal interface $internal"
        else
          reason="interface ''${pinned:-$routed} from the default route does not exist"
        fi
      else
        state=resolved
        reason=""
      fi

      # k=v form doubles as a systemd EnvironmentFile. Values are quoted since
      # they can contain spaces -- unquoted, `. stateFile` would run the second word as a command.
      tmp=$(mktemp)
      {
        printf 'uplink_ifaces="%s"\n' "$uplink_ifaces"
        printf 'uplink_state=%s\n' "$state"
        printf 'uplink_reason="%s"\n' "$reason"
      } >"$tmp"
      chmod 0644 "$tmp"

      # Preserve a pending change marker across an interrupted run, but don't
      # restart consumers again when the resolved state is unchanged.
      if [ ! -r ${stateFile} ] || [ "$(cat ${stateFile})" != "$(cat "$tmp")" ]; then
        : >${changedFlag}
      fi
      mv -f "$tmp" ${stateFile}

      if [ "$state" = resolved ]; then
        echo "ghaf-uplink: uplink(s): $uplink_ifaces"
        # ConditionPathExists on this flag gives dependents a visible "skipped,
        # no uplink" state instead of a spurious failure.
        : >${readyFlag}
      else
        echo "ghaf-uplink: no uplink -- $reason" >&2
        rm -f ${readyFlag}
      fi

      # Still honoured -- an explicit setting should win -- but not silently.
      if [ -n "$pinned" ] && [ -n "$routed" ] && [ "$pinned" != "$routed" ]; then
        echo "ghaf-uplink: WARNING uplink is pinned to '$pinned' but the default route is on '$routed'" >&2
        echo "ghaf-uplink: WARNING multicast and NAT will be applied to '$pinned', which is probably not what carries the LAN" >&2
      fi
    '';
  };

  dispatcher = pkgs.writeShellScript "ghaf-uplink-dispatcher" ''
    # NetworkManager owns the external NIC; its dispatcher fires on address
    # change, not merely device-added. $1 = interface, $2 = action.
    case "$2" in
      up | down | dhcp4-change | dhcp6-change | connectivity-change)
        ${pkgs.systemd}/bin/systemctl restart --no-block ghaf-uplink-resolver.service || true
        ;;
    esac
  '';
in
{
  _file = ./uplink-resolver.nix;

  options.ghaf.networking.uplinkResolver = {
    enable = mkEnableOption "resolving the LAN-facing interface at runtime";

    internalInterface = mkOption {
      type = types.str;
      default = "ethint0";
      description = ''
        The guest-facing interface, which is never the uplink.
      '';
    };

    forceInterface = mkOption {
      type = types.str;
      default = "";
      example = "enp1s0f0";
      description = ''
        Pin the uplink to a named interface instead of following the default
        route. Empty (the default) means resolve it.

        Consumers that expose an explicit "external NIC" setting wire it here
        rather than using it directly, so that there is exactly one place the
        uplink is decided. A pin that some consumers honoured and others
        ignored would be its own silent-wrongness bug.

        The resolver still checks the interface exists, and still warns when a
        pinned interface is not the one carrying the default route.
      '';
    };

    stateFile = mkOption {
      type = types.path;
      default = stateFile;
      readOnly = true;
      description = ''
        Where the resolved uplink is published, in `key=value` form. Readable as
        a systemd `EnvironmentFile`.
      '';
    };

    readyFlag = mkOption {
      type = types.path;
      default = readyFlag;
      readOnly = true;
      description = ''
        Present only while an uplink is resolved. Units that require the uplink
        should use `ConditionPathExists` on this, so that "no uplink" presents as
        a visible skip rather than as a failure or a silent no-op.
      '';
    };

    dependentUnits = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "smcroute.service" ];
      description = ''
        Units to restart after the uplink changes. Consumers add themselves
        here, so that this module needs no knowledge of them.

        Restarted rather than merely reloaded because the uplink appears in
        generated configuration, not just at runtime. A unit whose
        `ConditionPathExists` is unmet is skipped by systemd, which is the
        intended "no uplink" behaviour.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.ghaf-uplink-resolver = {
      description = "Resolve the LAN-facing (uplink) interface";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # No start rate limit: NetworkManager events (dock, DHCP renew, roam)
      # can easily exceed systemd's default 5 starts per 10s.
      unitConfig.StartLimitIntervalSec = 0;

      # Not ordered after network-online.target: reporting "no uplink" early
      # beats waiting out that target's full timeout on an uplink-less device.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe resolver;

        # Rapid dispatcher events at boot can SIGTERM an in-flight ExecStart.
        SuccessExitStatus = "SIGTERM";
      }
      // lib.optionalAttrs (cfg.dependentUnits != [ ]) {
        # `restart`, not `try-restart`: a dependent skipped for no uplink must
        # actually start once the flag appears. --no-block avoids deadlocking
        # against the resolver these units depend on.
        #
        # Restart before clearing the flag: an interrupting SIGTERM (see
        # SuccessExitStatus) then leaves the flag standing for a retry, rather
        # than landing between "flag gone" and "dependents restarted".
        ExecStartPost = pkgs.writeShellScript "ghaf-restart-uplink-dependents" ''
          if [ -e ${changedFlag} ]; then
            ${pkgs.systemd}/bin/systemctl restart --no-block ${lib.escapeShellArgs cfg.dependentUnits}
            rm -f ${changedFlag}
          fi
        '';
      };
    };

    networking.networkmanager.dispatcherScripts = [
      {
        source = dispatcher;
        type = "basic";
      }
    ];

    environment.etc."ghaf/uplink-resolver-README".text = ''
      The current uplink(s) are published at ${stateFile} as uplink_ifaces,
      a space-separated list of every interface currently holding a default
      route.
      ${readyFlag} exists only while at least one uplink is resolved.
      Run `systemctl status ghaf-uplink-resolver` or `cat ${stateFile}` to see it.
    '';
  };
}
