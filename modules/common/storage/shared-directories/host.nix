# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Host-side shared directories configuration module
#
{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.storage.shared-directories;
  builders = import ./builders.nix { inherit lib; };

  # Environment detection
  isHost = options.ghaf.virtualization ? microvm-host;
  inherit (config.networking) hostName;

  # Channel filtering
  fallbackChannels = lib.filterAttrs (_: builders.isFallbackMode) cfg.channels;
  nonFallbackChannels = lib.filterAttrs (_: ch: !builders.isFallbackMode ch) cfg.channels;
  hasFallbackChannels = fallbackChannels != { };
  hasNonFallbackChannels = nonFallbackChannels != { };

  # Guest notification helpers
  getVmCid = name: config.ghaf.networking.hosts.${name}.cid or null;
  getNotifyGuestCids =
    channelCfg:
    lib.pipe
      [ channelCfg.readWrite channelCfg.readOnly ]
      [
        (lib.concatMap (
          attrs: lib.attrNames (lib.filterAttrs (n: c: n != hostName && (c.notify or false)) attrs)
        ))
        lib.unique
        (map getVmCid)
        (lib.filter (cid: cid != null))
      ];

  # Build all tmpfile rules using builder
  allTmpfileRules = lib.flatten (
    lib.mapAttrsToList (
      name: ch:
      builders.mkHostTmpfileRules {
        channel = name;
        channelCfg = ch;
        inherit (cfg) baseDirectory;
        hostId = hostName;
      }
    ) cfg.channels
  );

  # Build all mounts using builder
  allMounts = lib.flatten (
    lib.mapAttrsToList (
      name: ch:
      builders.mkHostMounts {
        channel = name;
        channelCfg = ch;
        inherit (cfg) baseDirectory;
        hostId = hostName;
      }
    ) cfg.channels
  );

  # Build all assertions using builder
  allAssertions = lib.flatten (
    lib.mapAttrsToList (
      name: ch:
      builders.mkChannelAssertions {
        channel = name;
        channelCfg = ch;
        hostId = hostName;
      }
    ) cfg.channels
  );

  # Build daemon configuration using builder
  daemonConfig = lib.mapAttrs (
    name: ch:
    builders.mkDaemonChannelConfig {
      channel = name;
      channelCfg = ch;
      inherit (cfg) baseDirectory;
      guestCids = getNotifyGuestCids ch;
    }
  ) nonFallbackChannels;

in
{
  config = lib.mkIf (cfg.enable && isHost && cfg.channels != { }) {

    # Warn about potentially insecure configuration
    warnings =
      lib.optionals hasFallbackChannels [
        ''
          The following shared directories use 'fallback' mode which provides no isolation or scanning:
          ${lib.concatStringsSep ", " (lib.attrNames fallbackChannels)}
          Consider using 'untrusted' or 'trusted' mode instead to explicitly define the trust relationship.
        ''
      ]
      ++ lib.optionals (hasNonFallbackChannels && !cfg.scanner.enable) [
        ''
          Malware scanner is DISABLED. No channels - regardless of their configuration - will be scanned.
        ''
      ];

    # Channel validation assertions
    assertions = allAssertions;

    # Host directory structure
    systemd.tmpfiles.rules = [ "d ${cfg.baseDirectory} 0755 root root -" ] ++ allTmpfileRules;

    # Bind mounts
    systemd.mounts = allMounts;

    # Daemon configuration in /etc
    environment.etc."virtiofs-gate/config.json" = lib.mkIf hasNonFallbackChannels {
      text = builtins.toJSON daemonConfig;
    };

    # Virtiofs gate daemon
    systemd.services.virtiofs-gate-daemon = lib.mkIf hasNonFallbackChannels {
      description = "Virtiofs Gateway Daemon";
      wantedBy = [ "local-fs.target" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      before = lib.optionals config.ghaf.logging.fss.enable [ "journal-fss-setup.service" ];
      serviceConfig = {
        ExecStart =
          "${lib.getExe' pkgs.ghaf-virtiofs-tools "virtiofs-gate"} run --config /etc/virtiofs-gate/config.json"
          + lib.optionalString cfg.debug " --debug"
          + lib.optionalString (!cfg.scanner.enable) " --no-scan";
        Restart = "always";
        RestartSec = "5s";
        User = "root";
        Group = "root";
      };
    };
  };
}
