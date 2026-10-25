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
#
# A fleet with no reachable upstream at all is served by ghaf.time.server
# .operatorClock, which is deliberately a runtime vouch rather than a setting:
# see the comment on that option.
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

  # Survives a reboot only where the RTC does; see server.operatorClock.persist.
  vouchMarker = "/var/lib/ghaf-time/operator-vouched";

  # The vouch, as a command rather than a setting: a build cannot attest to a
  # clock. With no argument it serves the clock as it stands, which is the boot
  # path on hardware whose RTC held the operator's last value.
  setOperatorClock = pkgs.writeShellApplication {
    name = "ghaf-set-operator-clock";
    runtimeInputs = [
      pkgs.coreutils
      config.services.chrony.package
    ];
    text = ''
      # usage: ghaf-set-operator-clock [<date -s argument>]
      if [ "$#" -gt 0 ]; then
        date -s "$1" >/dev/null
      fi

      # `local` only now, and never from chrony.conf: between chronyd starting
      # and this running, the machine must not answer a client with a clock
      # nobody has vouched for.
      chronyc -m "local stratum ${toString cfg.server.operatorClock.stratum}" >/dev/null
      ${lib.optionalString cfg.server.operatorClock.persist ''
        mkdir -p "$(dirname ${lib.escapeShellArg vouchMarker})"
        : > ${lib.escapeShellArg vouchMarker}
      ''}
      echo "serving the operator's clock at stratum ${toString cfg.server.operatorClock.stratum}:" \
           "$(date -u -Is)"
    '';
  };
in
{
  _file = ./default.nix;

  options.ghaf.time = {
    enable = (mkEnableOption "Ghaf time synchronisation and the clock barrier") // {
      default = true;
    };

    requireSync = mkOption {
      type = types.bool;
      default = pkgs.stdenv.hostPlatform.isAarch64;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isAarch64";
      description = ''
        Whether the clock barrier blocks indefinitely, or releases after
        `syncWaitSeconds` even while the clock is still unsynchronised.

        On a board with no RTC backup cell the boot clock is wrong, not just
        imprecise, and only `NTPSynchronized` can tell -- so the barrier must
        hold, or consumers gated on `ghaf-clock-synced.target` (SPIRE among them)
        mint credentials that are already expired once the clock is corrected.
        A board with a battery-backed RTC boots at roughly the right time, so an
        unbounded wait there only stalls those consumers when offline, for no gain.

        The default uses architecture as a proxy for "has a battery-backed RTC":
        aarch64 is Jetson/Orin, which has none; x86 keeps its RTC across a cold
        boot. A board that breaks this assumption sets `requireSync` explicitly
        in its hardware module.
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

      # Serving a clock no upstream ever confirmed is the one thing this module
      # refuses by default, so the escape hatch is a runtime act, not a setting.
      operatorClock = {
        enable = mkEnableOption ''
          serving a clock an operator set by hand, for a fleet whose upstream is
          never reachable.

          chronyd still starts with no `local` reference: until an operator
          vouches for the clock by running `ghaf-set-operator-clock`, this
          machine has no source, answers no client, and the barrier holds
          exactly as it does today. The vouch is the whole difference between
          "this clock is wrong and nobody has said otherwise" and "a human is
          accountable for it", and it is why this is safe where a static
          `local stratum N` is not.

          A reachable upstream still wins, so this is a fallback rather than a
          replacement for one.
        '';

        stratum = mkOption {
          type = types.int;
          default = 10;
          description = ''
            Stratum to report once an operator has vouched. The default is far
            enough down that any real upstream appearing later takes over.
          '';
        };

        persist = mkOption {
          type = types.bool;
          default = !cfg.requireSync;
          defaultText = lib.literalExpression "!config.ghaf.time.requireSync";
          description = ''
            Whether a vouch survives a reboot.

            It may only where the hardware keeps time across a power cycle, so
            this follows the same battery-backed-RTC proxy as `requireSync`: a
            board without a cell boots at the fallback epoch, and re-serving a
            vouch there would publish that epoch to the fleet -- the precise
            failure the barrier exists to catch. Where the RTC is trustworthy
            the operator's time is still on it after a reboot, so re-serving it
            is honest and saves asking them again.
          '';
        };
      };

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
        # Not in the server branch below: there the implication is already
        # satisfied, so the assertion could never fail.
        assertions = [
          {
            assertion = cfg.server.operatorClock.enable -> cfg.server.enable;
            message = "ghaf.time.server.operatorClock serves the fleet from the machine that runs chrony, so it needs ghaf.time.server.enable on the same host.";
          }
        ];

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
                runtimeInputs =
                  with pkgs;
                  [
                    coreutils
                    gawk
                    systemd
                  ]
                  ++ lib.optional cfg.server.enable config.services.chrony.package;
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
                    if ${
                      if cfg.server.enable then
                        "chronyc waitsync 1 0 0 0.1 >/dev/null 2>&1"
                      else
                        ''[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" = "yes" ]''
                    }; then
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
          # Allow clients to synchronize promptly while net-vm's clock stabilizes.
          #
          # The poll interval governs how often a client retries a server it has
          # rejected, so it sets how long a client waits out the server's initial
          # convergence. Measured on an X1 with PollIntervalMaxSec=32s: three
          # "Server has too large root distance" rejections 32.25s apart, and the
          # first accepted reply only at 127s. Keeping the ceiling next to the
          # floor roughly halves that.
          #
          # Keep both limits at 16s. timesyncd doubles the current interval before
          # checking it against the maximum, so a 16s/17s range actually retries
          # after 32s. Equal limits are accepted and prevent that overshoot.
          settings.Time = {
            RootDistanceMaxSec = "30s";
            PollIntervalMinSec = "16s";
            PollIntervalMaxSec = "16s";
            ConnectionRetrySec = "5s";
          };
        };
      })

      (mkIf cfg.server.enable {
        # chrony's upstream time sources.
        ghaf.firewall.allowedUDPPorts = [
          {
            port = 123;
            direction = "output";
          }
        ];

        # Without its driftfile chronyd re-estimates frequency and skew from
        # scratch on every boot, and until it converges its root dispersion stays
        # above the clients' RootDistanceMaxSec -- so the whole fleet waits on a
        # server that is running but not yet acceptable. Observed on an X1 as
        # "Could not read valid frequency and skew from driftfile" followed by
        # clients rejecting net-vm for ~96s.
        #
        # rtcfile is persisted for the same reason: it is what lets chronyd
        # correct the RTC at shutdown and trust it at the next boot.
        ghaf.storagevm.directories = lib.mkIf config.ghaf.storagevm.enable (
          [
            {
              directory = "/var/lib/chrony";
              user = "chrony";
              group = "chrony";
              mode = "0750";
            }
          ]
          ++ lib.optional (cfg.server.operatorClock.enable && cfg.server.operatorClock.persist) {
            directory = dirOf vouchMarker;
            mode = "0755";
          }
        );

        environment.systemPackages = lib.mkIf cfg.server.operatorClock.enable [ setOperatorClock ];

        services.timesyncd.enable = false;
        services.chrony = {
          enable = true;
          servers = cfg.upstreamServers;
          extraConfig = ''
            ${lib.concatMapStringsSep "\n" (net: "allow ${net}") cfg.server.allowedNetworks}

            makestep 1.0 -1
          '';
        };

        # Without this chronyd backs off resolving and polling, so sync lags the uplink by ~30s or more.
        systemd.services =
          lib.mapAttrs
            (_: cmds: {
              description = "Tell chronyd the network configuration changed";
              after = [ "chronyd.service" ];
              requisite = [ "chronyd.service" ];
              unitConfig = {
                StartLimitIntervalSec = 1;
                StartLimitBurst = 10;
              };
              serviceConfig = {
                Type = "oneshot";
                ExecStart = map (cmd: "${lib.getExe' config.services.chrony.package "chronyc"} ${cmd}") cmds;
              };
            })
            {
              ghaf-chrony-onoffline = [
                "onoffline"
                "burst 4/10"
              ];
              # Re-resolving replaces sources and drops their samples, so only do it when DNS changed.
              ghaf-chrony-refresh = [ "refresh" ];
            };

        # chronyc cannot run inside the dispatcher's sandbox, so start a unit instead.
        networking.networkmanager.dispatcherScripts = mkIf config.networking.networkmanager.enable [
          {
            type = "basic";
            source = pkgs.writeShellScript "ghaf-chrony-dispatcher" ''
              case "$2" in
                up | down | connectivity-change)
                  ${lib.getExe' pkgs.systemd "systemctl"} restart --no-block ghaf-chrony-onoffline.service
                  ;;
                dhcp4-change | dhcp6-change | dns-change)
                  ${lib.getExe' pkgs.systemd "systemctl"} restart --no-block ghaf-chrony-refresh.service
                  ;;
              esac
            '';
          }
        ];
      })

      # Its own mkMerge element
      (mkIf (cfg.server.enable && cfg.server.operatorClock.enable && cfg.server.operatorClock.persist) {
        systemd.services.ghaf-restore-operator-clock = {
          description = "Serve the operator's vouched clock again after a reboot";
          wantedBy = [ "ghaf-clock-synced.target" ];
          before = [ "ghaf-wait-time-sync.service" ];
          after = [ "chronyd.service" ];
          requires = [ "chronyd.service" ];
          unitConfig.ConditionPathExists = vouchMarker;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe setOperatorClock;
          };
        };
      })
    ]
  );
}
