# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf.time: fleet time source and the "clock is trustworthy" barrier.
#
# Jetsons ship without an RTC backup cell, so every boot starts at a fixed
# fallback epoch and only reaches real time once NTP has answered. Anything that
# mints short-lived credentials in that window produces artefacts that are
# already expired the moment the clock is corrected -- observed on an Orin AGX as
# SPIRE SVIDs with a 24h TTL issued at 2026-03-17 and dead ~4.5 months before the
# system had finished booting.
#
# This module provides the barrier such consumers order themselves after, and the
# internal time source that makes the barrier reachable without direct internet.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.time;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;
in
{
  _file = ./default.nix;

  options.ghaf.time = {
    enable = (mkEnableOption "Ghaf time synchronisation and the clock barrier") // {
      default = true;
    };

    requireSync = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the clock barrier blocks indefinitely until the system clock is
        actually synchronised.

        With no RTC backup cell the clock is wrong -- not merely imprecise -- for
        the first seconds of every boot, and a plausibility range cannot detect
        that: the fallback epoch reads as an ordinary recent date. Only
        `NTPSynchronized` distinguishes the two.

        Leave this on. Turn it off only for a device with no reachable time
        source at all, accepting that consumers gated on
        `ghaf-clock-synced.target` may then run against an untrusted clock.
      '';
    };

    syncWaitSeconds = mkOption {
      type = types.int;
      default = 180;
      description = ''
        Bound on the barrier wait when `requireSync` is false. Ignored when
        `requireSync` is true, where the wait is deliberately unbounded.
      '';
    };

    servers = mkOption {
      type = types.listOf types.str;
      default = [ (config.ghaf.networking.hosts."net-vm".ipv4 or "192.168.100.1") ];
      defaultText = lib.literalExpression ''[ config.ghaf.networking.hosts."net-vm".ipv4 ]'';
      description = ''
        Time servers this machine synchronises against. Defaults to net-vm, which
        holds the physical uplink and serves the internal network.
      '';
    };

    upstreamServers = mkOption {
      type = types.listOf types.str;
      default = [
        "0.nixos.pool.ntp.org"
        "1.nixos.pool.ntp.org"
        "2.nixos.pool.ntp.org"
        "3.nixos.pool.ntp.org"
      ];
      description = ''
        Upstream time sources used by the machine that serves the fleet. Point
        this at a lab NTP server on networks without direct internet access.
      '';
    };

    server = {
      enable = mkEnableOption "serving time to the internal network from this machine";

      allowedNetworks = mkOption {
        type = types.listOf types.str;
        default = [ "192.168.100.0/24" ];
        description = "Networks permitted to query this machine for time.";
      };
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      # Clients follow ghaf.time.servers; the fleet's time source follows its
      # upstream instead. systemd-timesyncd is a client only and cannot answer
      # queries, so the server side runs chrony.
      {
        systemd.services.ghaf-wait-time-sync = {
          description = "Wait for the system clock to be synchronised";
          wantedBy = [ "ghaf-clock-synced.target" ];
          before = [ "ghaf-clock-synced.target" ];
          after = [
            "network-online.target"
            "systemd-timesyncd.service"
            "chronyd.service"
          ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # Unbounded on purpose when requireSync is set: a timeout here would
            # release exactly the consumers this barrier exists to hold back.
            TimeoutStartSec = if cfg.requireSync then "infinity" else "${toString (cfg.syncWaitSeconds + 30)}s";
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "ghaf-wait-time-sync";
                runtimeInputs = with pkgs; [
                  coreutils
                  gawk
                  systemd
                ];
                # The bounded-wait branch is emitted only when requireSync is
                # false. Declaring its state unconditionally would leave unused
                # variables in the requireSync case, and writeShellApplication
                # runs shellcheck, so SC2034 fails the build outright.
                text = ''
                  synced_file="/run/ghaf-clock-synced"
                  ${optionalString (!cfg.requireSync) ''
                    wait_seconds="${toString cfg.syncWaitSeconds}"

                    uptime_seconds() {
                      awk '{printf "%d\n", $1}' /proc/uptime
                    }

                    start_up="$(uptime_seconds)"
                  ''}

                  while true; do
                    value="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
                    if [ "$value" = "yes" ]; then
                      echo "Clock synchronised; realtime is $(date -u -Is)"
                      printf 'synchronised\n' > "$synced_file"
                      break
                    fi

                    ${optionalString (!cfg.requireSync) ''
                      if [ "$(( $(uptime_seconds) - start_up ))" -ge "$wait_seconds" ]; then
                        echo "WARNING: releasing clock barrier unsynchronised after $wait_seconds s;" \
                             "consumers may mint credentials against an untrusted clock"
                        printf 'released\n' > "$synced_file"
                        break
                      fi
                    ''}

                    sleep 1
                  done

                  chmod 0644 "$synced_file"
                '';
              }
            );
          };
        };

        # Consumers order themselves after this target rather than after the
        # service, so the wait implementation can change without touching them.
        systemd.targets.ghaf-clock-synced = {
          description = "Ghaf trusted clock barrier";
          requires = [ "ghaf-wait-time-sync.service" ];
          after = [ "ghaf-wait-time-sync.service" ];
        };
      }

      (mkIf (!cfg.server.enable) {
        services.timesyncd = {
          enable = lib.mkDefault true;
          inherit (cfg) servers;
          # No public fallback: a client that silently reaches the internet instead
          # of net-vm hides a broken internal time path until something expires.
          fallbackServers = [ ];
        };
      })

      (mkIf cfg.server.enable {
        services.timesyncd.enable = false;
        services.chrony = {
          enable = true;
          servers = cfg.upstreamServers;
          extraConfig = ''
            ${lib.concatMapStringsSep "\n" (net: "allow ${net}") cfg.server.allowedNetworks}

            # Deliberately no `local stratum N` fallback. It would make chronyd
            # serve this machine's own clock as authoritative when upstream is
            # unreachable -- which, on a device with no RTC cell, is the boot-time
            # fallback epoch. Clients would sync to it, report NTPSynchronized=yes
            # against a wrong time, and sail straight through the barrier: exactly
            # the failure this module exists to prevent, only now fleet-wide and
            # harder to spot. With no upstream the honest outcome is that nothing
            # synchronises and the barrier holds; ghaf.time.requireSync = false is
            # the deliberate escape hatch for a device with no time source.

            # The uplink may appear well after chronyd starts, and the first
            # correction out of the fallback epoch is far too large for slewing.
            makestep 1.0 -1
          '';
        };
      })
    ]
  );
}
