# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Resolves which interface currently carries the LAN ("the uplink") and publishes
# it for other units to consume.
#
# Why this exists: chromecast, dendrite-pinecone and wireguard-gui take the
# uplink from a *build-time* expression,
#   (lib.head config.ghaf.hardware.definition.network.pciDevices).name
# which enumerates PCI-passthrough NICs and is therefore structurally the Wi-Fi
# card. Ethernet arrives as a dock or USB dongle via vhotplug at runtime and has
# no entry in that list at all, so on a wired device the baked name is simply
# wrong and those services wait forever for an address that never appears.
#
# The uplink is a runtime fact, so it has to be resolved at runtime.
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
      # The uplink is the interface holding the default route: it is the only
      # definition that always agrees with where traffic actually goes, and it
      # follows a dock being plugged in or pulled out without any extra state.
      #
      # A device can carry more than one default route at once (Wi-Fi and a
      # docked Ethernet both up), so this resolves *every* usable one, not
      # just the first. `ifaces`/`uplink_ifaces` is the full list every
      # consumer (nw-packet-forwarder, smcroute, the firewall, etc.) acts on.
      internal=${lib.escapeShellArg cfg.internalInterface}
      pinned=${lib.escapeShellArg cfg.forceInterface}

      # `ip route show default` already restricts to default-route lines; the
      # `dev` field position varies (e.g. a gateway-less
      # `default dev wlan0 scope link` has no `via`), so search for the `dev`
      # token instead of assuming a fixed column.
      mapfile -t routed_list < <(ip route show default 2>/dev/null \
        | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); break}}')
      routed="''${routed_list[0]:-}"

      candidate_ok() {
        # ethint0 faces the guest VMs, never the LAN. If it somehow holds the
        # default route the routing table is wrong, and claiming it as the
        # uplink would bridge multicast straight back inwards.
        [ "$1" != "$internal" ] && [ -e "/sys/class/net/$1" ]
      }

      ifaces=()
      if [ -n "$pinned" ]; then
        # An explicit pin wins outright -- see the disagreement warning below
        # for why that's still not silent.
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

      # Written in k=v form so it doubles as a systemd EnvironmentFile.
      # uplink_ifaces and uplink_reason are quoted since both can contain
      # spaces (a multi-interface list, a multi-word reason like "no default
      # route") -- unquoted, `. stateFile` parses the second word as a
      # command to run, not part of the value. nw-packet-forwarder-reconcile
      # is the one consumer not gated by the ready flag (it has to run to
      # tear down when the uplink disappears), so it's the one that actually
      # sources the file in state=none and hits this.
      tmp=$(mktemp)
      {
        printf 'uplink_ifaces="%s"\n' "$uplink_ifaces"
        printf 'uplink_state=%s\n' "$state"
        printf 'uplink_reason="%s"\n' "$reason"
      } >"$tmp"
      chmod 0644 "$tmp"

      # NetworkManager can emit several dispatcher events for one transition
      # (up, DHCP change and connectivity change). Preserve a pending change
      # marker across an interrupted resolver run, but do not restart consumers
      # again when the resolved state is identical.
      if [ ! -r ${stateFile} ] || [ "$(cat ${stateFile})" != "$(cat "$tmp")" ]; then
        : >${changedFlag}
      fi
      mv -f "$tmp" ${stateFile}

      if [ "$state" = resolved ]; then
        echo "ghaf-uplink: uplink(s): $uplink_ifaces"
        # The flag file is the readiness signal. Units that need the uplink use
        # ConditionPathExists on it, which gives them a third state -- "skipped,
        # because there is no uplink" -- that is visible in systemctl status and
        # in the journal, without being a spurious failure. An unplugged dock is
        # a legitimate transient state, not a defect.
        : >${readyFlag}
      else
        echo "ghaf-uplink: no uplink -- $reason" >&2
        rm -f ${readyFlag}
      fi

      # A pin that disagrees with where traffic actually goes is the original
      # bug in miniature, so say so rather than letting it pass quietly. It is
      # still honoured -- an explicit setting should win -- but not silently.
      if [ -n "$pinned" ] && [ -n "$routed" ] && [ "$pinned" != "$routed" ]; then
        echo "ghaf-uplink: WARNING uplink is pinned to '$pinned' but the default route is on '$routed'" >&2
        echo "ghaf-uplink: WARNING multicast and NAT will be applied to '$pinned', which is probably not what carries the LAN" >&2
      fi
    '';
  };

  dispatcher = pkgs.writeShellScript "ghaf-uplink-dispatcher" ''
    # NetworkManager owns the external NIC in net-vm (systemd-networkd owns only
    # ethint0), so its dispatcher is the precise trigger: it fires when an
    # address appears or goes away, not merely when a device is added.
    # $1 = interface, $2 = action.
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

      # No start rate limit. This unit is driven by NetworkManager events, and a
      # dock being plugged in, a DHCP renew or a wifi roam can easily produce
      # more than systemd's default 5 starts per 10s. Hitting that limit makes
      # systemd refuse to run it.
      unitConfig.StartLimitIntervalSec = 0;

      # Deliberately not ordered after network-online.target: on a device whose
      # uplink is absent that target can take its full timeout, and the resolver
      # reporting "no uplink" early is more useful than reporting it late.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe resolver;

        # The NetworkManager dispatcher restarts this unit on every up /
        # dhcp4-change / connectivity-change event, and at boot those arrive
        # faster than one run completes -- so systemd SIGTERMs the in-flight
        # ExecStart or ExecStartPost and records "Failed with result 'signal'"
        SuccessExitStatus = "SIGTERM";
      }
      // lib.optionalAttrs (cfg.dependentUnits != [ ]) {
        # `restart` rather than `try-restart`: a dependent that was skipped for
        # lack of an uplink is not running, and must actually be started once
        # the flag appears -- try-restart would leave it stopped. When the
        # uplink goes away the flag is gone, so the start half is skipped by
        # ConditionPathExists and the unit correctly ends up stopped.
        # --no-block avoids deadlocking against the resolver they depend on.
        #
        # Restart before clearing the flag, not after: NetworkManager can
        # fire several dispatcher events within the same second, each
        # restarting this unit and SIGTERMing whichever invocation (ExecStart
        # or ExecStartPost) is still in flight -- that is what
        # SuccessExitStatus above is for. Clearing the flag first would let
        # that SIGTERM land between "flag gone" and "dependents actually
        # restarted", silently dropping the update the flag was recording.
        # Restarting first means an interruption right there just leaves the
        # flag standing, so the next invocation (already on its way, given
        # the burst that caused the interruption) retries it.
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
