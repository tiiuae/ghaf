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
      internal=${lib.escapeShellArg cfg.internalInterface}
      expected=${lib.escapeShellArg cfg.expectedInterface}

      iface=$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')

      state=resolved
      reason=""

      if [ -z "$iface" ]; then
        state=none
        reason="no default route"
      elif [ "$iface" = "$internal" ]; then
        # ethint0 faces the guest VMs, never the LAN. If it somehow holds the
        # default route the routing table is wrong, and claiming it as the
        # uplink would bridge multicast straight back inwards.
        state=none
        reason="default route is on the internal interface $internal"
        iface=""
      elif [ ! -e "/sys/class/net/$iface" ]; then
        state=none
        reason="interface $iface from the default route does not exist"
        iface=""
      fi

      # Written in k=v form so it doubles as a systemd EnvironmentFile.
      tmp=$(mktemp)
      {
        printf 'uplink_iface=%s\n' "$iface"
        printf 'uplink_state=%s\n' "$state"
        printf 'uplink_reason=%s\n' "$reason"
      } >"$tmp"
      chmod 0644 "$tmp"
      mv -f "$tmp" ${stateFile}

      if [ "$state" = resolved ]; then
        echo "ghaf-uplink: uplink is $iface"
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

      # Phase 1 is deliberately observation-only: nothing is reconfigured yet.
      # This warning is the whole point of the phase -- it turns a silently wrong
      # interface into a visible, greppable fact on every affected device.
      if [ -n "$expected" ] && [ "$state" = resolved ] && [ "$iface" != "$expected" ]; then
        echo "ghaf-uplink: WARNING configured externalNic is '$expected' but the uplink is '$iface'" >&2
        echo "ghaf-uplink: WARNING services bound to '$expected' (chromecast, smcroute, nw-packet-forwarder) cannot work on this device" >&2
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

    expectedInterface = mkOption {
      type = types.str;
      default = "";
      description = ''
        The interface name that build-time configuration assumed. When set and
        it disagrees with the resolved uplink, the resolver logs a warning.
        Purely diagnostic; nothing is reconfigured on the strength of it.
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
  };

  config = mkIf cfg.enable {
    systemd.services.ghaf-uplink-resolver = {
      description = "Resolve the LAN-facing (uplink) interface";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # Deliberately not ordered after network-online.target: on a device whose
      # uplink is absent that target can take its full timeout, and the resolver
      # reporting "no uplink" early is more useful than reporting it late.
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe resolver;
      };
    };

    networking.networkmanager.dispatcherScripts = [
      {
        source = dispatcher;
        type = "basic";
      }
    ];

    environment.etc."ghaf/uplink-resolver-README".text = ''
      The current uplink is published at ${stateFile}.
      ${readyFlag} exists only while an uplink is resolved.
      Run `systemctl status ghaf-uplink-resolver` or `cat ${stateFile}` to see it.
    '';
  };
}
