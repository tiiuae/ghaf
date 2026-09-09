# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
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
    types
    mkIf
    optionalString
    ;
  cfg = config.services.nw-packet-forwarder;

  chromecastVmIpAddr = config.ghaf.networking.hosts.${cfg.chromecast.vmName}.ipv4;
  chromecastVmMac = config.ghaf.networking.hosts.${cfg.chromecast.vmName}.mac;
  netVmInternalIp = config.ghaf.networking.hosts."net-vm".ipv4;
  chromecastFlags = optionalString cfg.chromecast.enable ''
    --ccastvm-mac ${chromecastVmMac} \
    --ccastvm-ip ${chromecastVmIpAddr}/24
  '';

  # One forwarder process per resolved uplink, run from a template unit so a
  # device with several simultaneous uplinks (Wi-Fi and a docked Ethernet,
  # say) forwards on all of them instead of only the lowest-metric one. `%I`
  # carries the external interface name; it is passed as an argv element
  # rather than spliced into this string so it can't collide with the
  # `chromecastFlags` backslash-continuations below.
  nw-pckt-fwd-instance = pkgs.writeShellScriptBin "nw-pckt-fwd-instance" ''
    external_iface="$1"
    echo "nw-pckt-fwd: forwarding between $external_iface and ${cfg.internalNic}"
    exec ${pkgs.ghaf-nw-packet-forwarder}/bin/nw-pckt-fwd \
    --external-iface "$external_iface" \
    --internal-iface ${cfg.internalNic} \
    --internal-ip ${cfg.internalIp} ${chromecastFlags}
  '';

  # Starts/stops nw-packet-forwarder@<iface> instances to match
  # uplink_ifaces. Deliberately not gated on the ready flag (unlike the
  # forwarder instances themselves): it must still run when there is no
  # uplink at all, so it can stop every instance left over from one that just
  # disappeared -- its own start/stop diff already reduces to "stop
  # everything" when the desired set is empty.
  nw-packet-forwarder-reconcile-script = pkgs.writeShellApplication {
    name = "nw-packet-forwarder-reconcile";
    runtimeInputs = [
      pkgs.systemd
      pkgs.gawk
      pkgs.gnused
    ];
    text = ''
      uplink_ifaces=""
      if [ -r ${cfg.stateFile} ]; then
        # shellcheck disable=SC1090,SC1091
        . ${cfg.stateFile}
      fi
      read -ra desired <<< "''${uplink_ifaces:-}"

      readarray -t running < <(systemctl list-units --plain --no-legend --state=active,activating \
        'nw-packet-forwarder@*.service' 2>/dev/null | awk '{print $1}' \
        | sed -e 's/^nw-packet-forwarder@//' -e 's/\.service$//')

      for iface in "''${desired[@]}"; do
        if ! systemctl is-active --quiet "nw-packet-forwarder@$iface.service"; then
          echo "nw-packet-forwarder-reconcile: starting forwarder on $iface"
          systemctl start --no-block "nw-packet-forwarder@$iface.service"
        fi
      done

      for iface in "''${running[@]}"; do
        wanted=0
        for d in "''${desired[@]}"; do
          if [ "$d" = "$iface" ]; then
            wanted=1
            break
          fi
        done
        if [ "$wanted" -eq 1 ]; then
          continue
        fi
        echo "nw-packet-forwarder-reconcile: stopping forwarder on $iface (no longer an uplink)"
        systemctl stop --no-block "nw-packet-forwarder@$iface.service"
      done
    '';
  };
in
{
  _file = ./nw-packet-forwarder.nix;

  options.services.nw-packet-forwarder = {
    enable = mkEnableOption "nw-packet-forwarder";
    confFile = mkOption {
      type = types.path;
      example = "/var/lib/nw-packet-forwarder/nw-packet-forwarder.conf";
      description = ''
        Ignore all other nw-packet-forwarder options and load configuration from this file.
      '';
    };

    internalNic = mkOption {
      type = types.str;
      default = "";
      example = "";
      description = ''
        Internal NIC
      '';
    };

    internalIp = mkOption {
      type = types.str;
      default = netVmInternalIp;
      example = "";
      description = ''
        Internal IP
      '';
    };
    chromecast = mkOption {
      description = "nw-packet-forwarder chromecast configuration";
      type = types.submodule {
        options = {
          enable = mkEnableOption "the Chromecast feature";

          vmName = mkOption {
            type = types.str;
            example = "chrome-vm";
            description = "The name of the chromium/chrome VM to setup Chromecast for.";
            default = "chrome-vm";
          };
        };
      };
    };

    stateFile = mkOption {
      type = types.path;
      default = "/run/ghaf-uplink-state";
      description = "Where the uplink resolver publishes the current uplink.";
    };

    readyFlag = mkOption {
      type = types.path;
      default = "/run/ghaf-uplink-ready";
      description = ''
        Gate for the reconciler and forwarder instances. Absent means there
        is no uplink, and instances are stopped rather than left running for
        a stale interface.
      '';
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.internalNic != "";
        message = "Internal Nic must be set";
      }
      {
        # No build-time fallback any more: every forwarder instance is
        # started by the reconciler off the resolver's state file. Without
        # the resolver actually running, the reconciler would never see any
        # uplink and no instance would ever start -- silently, not a failure.
        assertion = config.ghaf.networking.uplinkResolver.enable;
        message = ''
          services.nw-packet-forwarder.enable requires
          ghaf.networking.uplinkResolver.enable -- every forwarder instance is
          started off the resolved uplink, and without the resolver running
          no instance would ever start.
        '';
      }
    ];

    services.nw-packet-forwarder.confFile = lib.mkDefault (
      pkgs.writeText "nw-packet-forwarder.conf" ''
        # TODO: create config file if there are a lot of cli parameters
      ''
    );

    systemd.services = {
      # One instance per resolved uplink, started and stopped by the
      # reconciler below rather than by a static wantedBy/bindsTo -- a
      # template can't bindsTo a .device unit whose interface name isn't
      # known until the resolver runs.
      "nw-packet-forwarder@" = {
        description = "Network packet forwarder daemon (%i)";

        # No start rate limit: the reconciler starts/stops a specific
        # instance whenever its interface enters or leaves uplink_ifaces,
        # and NetworkManager can fire several dispatcher events for one
        # transition -- an interface flapping a few times in quick
        # succession would otherwise hit the limit and leave that instance
        # refusing to start for the rest of the window.
        unitConfig.StartLimitIntervalSec = 0;

        bindsTo = [ "sys-subsystem-net-devices-${cfg.internalNic}.device" ];
        after = [
          "sys-subsystem-net-devices-${cfg.internalNic}.device"
          "ghaf-uplink-resolver.service"
        ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${nw-pckt-fwd-instance}/bin/nw-pckt-fwd-instance %I";
          TimeoutStartSec = "0";
          Restart = "always";
          RestartSec = "15s";
        };
      };

      nw-packet-forwarder-reconcile = {
        description = "Reconcile nw-packet-forwarder instances with the resolved uplinks";
        after = [ "ghaf-uplink-resolver.service" ];
        # Restarted by the resolver's dependentUnits, potentially several
        # times per transition -- same reasoning as the template unit above.
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe nw-packet-forwarder-reconcile-script;
          ProtectSystem = "strict";
          NoNewPrivileges = true;
        };
      };
    };
  };
}
