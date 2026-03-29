# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-side shared directories configuration module
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
  isGuest = (options.microvm or { }) ? shares;
  vmName = config.networking.hostName;

  # Filter channels this VM participates in
  vmChannels = lib.filterAttrs (_: ch: builders.isInChannel ch vmName) cfg.channels;

  vmParticipates = vmChannels != { };

  # Build share configurations using builder
  shareConfigs = lib.mapAttrsToList (
    name: ch:
    builders.mkVmShareConfig {
      channel = name;
      channelCfg = ch;
      inherit vmName;
      inherit (cfg) baseDirectory;
    }
  ) vmChannels;

  # Build notification mappings using builder
  notifyMappings = lib.filter (x: x != { }) (
    lib.mapAttrsToList (
      name: ch:
      builders.mkVmNotifyMapping {
        channel = name;
        channelCfg = ch;
        inherit vmName;
      }
    ) vmChannels
  );
  vmWantsAnyNotify = notifyMappings != [ ];

in
{
  config = lib.optionalAttrs isGuest (
    lib.mkIf (cfg.enable && vmParticipates) {

      # Mount point directories
      systemd.tmpfiles.rules = map (c: c.tmpfileRule) shareConfigs;

      # Virtiofs notification receiver
      systemd.services.virtiofs-notify = lib.mkIf vmWantsAnyNotify {
        description = "Virtiofs notification receiver";
        after = [
          "network.target"
          "local-fs.target"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe' pkgs.ghaf-virtiofs-tools "virtiofs-notify"} ${
            lib.concatMapStringsSep " " (n: n.mapping) notifyMappings
          }";
          Restart = "on-failure";
          RestartSec = "5s";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      # Microvm shares and fileSystems config
      microvm.shares = map (c: c.share) shareConfigs;
      fileSystems = lib.listToAttrs (map (c: c.filesystem) shareConfigs);
    }
  );
}
