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
  # Seconds to wait for externalNic before giving up. Bounded on purpose: an
  # unbounded wait here logged "Waiting for IPv4 address on interface ..." every
  # 10s forever while the unit reported "active". Failing loudly once is more useful than
  # succeeding quietly at nothing.
  externalNicTimeout = 60;
  nw-pckt-fwd-launcher = pkgs.writeShellScriptBin "nw-pckt-fwd" (
    if cfg.uplink.enable then
      # The resolver has already established that this interface exists and
      # holds the default route, and ConditionPathExists gates the unit on that,
      # so there is nothing to wait for -- just read it and go.
      ''
        # shellcheck disable=SC1090
        . ${cfg.uplink.stateFile}
        if [ -z "''${uplink_iface:-}" ]; then
          echo "nw-pckt-fwd: ${cfg.uplink.stateFile} names no uplink; refusing to forward on a guess." >&2
          exit 1
        fi
        echo "nw-pckt-fwd: forwarding between $uplink_iface and ${cfg.internalNic}"
        exec ${pkgs.ghaf-nw-packet-forwarder}/bin/nw-pckt-fwd \
        --external-iface "$uplink_iface" \
        --internal-iface ${cfg.internalNic} \
        --internal-ip ${cfg.internalIp} ${chromecastFlags}
      ''
    else
      # Legacy path for a build-time externalNic, unchanged from the
      # bounded-wait fix.
      ''
        # Wait until the external interface has an IPv4 address (e.g. Wi-Fi connected).
        deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString externalNicTimeout} ))
        while [ -z "$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${cfg.externalNic} scope global 2>/dev/null)" ]; do
          if [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ]; then
            echo "nw-pckt-fwd: '${cfg.externalNic}' has no global IPv4 address after ${toString externalNicTimeout}s - giving up." >&2
            echo "nw-pckt-fwd: set services.nw-packet-forwarder.uplink.enable to resolve the interface at runtime instead." >&2
            exit 1
          fi
          echo "Waiting for IPv4 address on interface ${cfg.externalNic}..."
          sleep 10
        done

        exec ${pkgs.ghaf-nw-packet-forwarder}/bin/nw-pckt-fwd \
        --external-iface ${cfg.externalNic} \
        --internal-iface ${cfg.internalNic} \
        --internal-ip ${cfg.internalIp} ${chromecastFlags}
      ''
  );
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

    externalNic = mkOption {
      type = types.str;
      default = "";
      example = "";
      description = ''
        External NIC
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

    uplink = {
      enable = mkEnableOption ''
        taking the external interface from the runtime uplink resolver instead
        of `externalNic`
      '';

      stateFile = mkOption {
        type = types.path;
        default = "/run/ghaf-uplink-state";
        description = "Where the uplink resolver publishes the current uplink.";
      };

      readyFlag = mkOption {
        type = types.path;
        default = "/run/ghaf-uplink-ready";
        description = ''
          Gate for the unit. Absent means there is no uplink, and the unit is
          skipped rather than failed.
        '';
      };
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uplink.enable || cfg.externalNic != "";
        message = "External Nic must be set, or services.nw-packet-forwarder.uplink.enable used";
      }
      {
        assertion = cfg.internalNic != "";
        message = "Internal Nic must be set";
      }
    ];

    services.nw-packet-forwarder.confFile = lib.mkDefault (
      pkgs.writeText "nw-packet-forwarder.conf" ''
        # TODO: create config file if there are a lot of cli parameters
      ''
    );

    systemd.services."nw-packet-forwarder" = {
      description = "Network packet forwarder daemon";

      # Restart=always below has no natural end, so bounding the wait in the
      # launcher is not enough on its own -- without a start limit it would
      # simply trade a 10s log-spam loop for a 75s restart loop. Give up after
      # a few attempts so the unit lands in "failed" where it is visible.
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
      }
      // lib.optionalAttrs cfg.uplink.enable {
        # No uplink => skipped and visibly so, rather than failed (an unplugged
        # dock is not a defect) or silently active-doing-nothing (which is what
        # the unbounded wait amounted to).
        ConditionPathExists = cfg.uplink.readyFlag;
      };

      # The device units below bake an interface name into a *unit* name, which
      # cannot survive an interface resolved at runtime -- and a bindsTo on a
      # .device that never appears makes the unit unstartable. Under uplink.enable
      # the resolver plays that role instead: it only publishes an interface that
      # exists and holds the default route, and restarts this unit when that
      # changes. The internal NIC is static, so it keeps its device dependency.
      bindsTo =
        lib.optional (!cfg.uplink.enable) "sys-subsystem-net-devices-${cfg.externalNic}.device"
        ++ [ "sys-subsystem-net-devices-${cfg.internalNic}.device" ];
      after =
        lib.optional (!cfg.uplink.enable) "sys-subsystem-net-devices-${cfg.externalNic}.device"
        ++ [ "sys-subsystem-net-devices-${cfg.internalNic}.device" ]
        ++ lib.optional cfg.uplink.enable "ghaf-uplink-resolver.service";

      wantedBy = [
        "multi-user.target"
      ]
      ++ lib.optional (!cfg.uplink.enable) "sys-subsystem-net-devices-${cfg.externalNic}.device"
      ++ [ "sys-subsystem-net-devices-${cfg.internalNic}.device" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${nw-pckt-fwd-launcher}/bin/nw-pckt-fwd";
        TimeoutStartSec = "0";
        Restart = "always";
        RestartSec = "15s";
      };
    };

  };

}
