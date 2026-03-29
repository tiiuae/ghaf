# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Guest-specific ClamAV configuration
#
# Includes:
#   - ghaf.storagevm.directories for persistent storage
#   - Guest-specific systemd services if any
#
{
  config,
  lib,
  options,
  ...
}:
let
  inherit (lib)
    mkIf
    optionals
    ;

  cfg = config.ghaf.security.clamav;
  isHost = options.ghaf.virtualization ? microvm-host;
in
{
  _file = ./vm.nix;

  config = mkIf (cfg.enable && !isHost) {
    ghaf.storagevm.directories =
      optionals cfg.daemon.enable [
        {
          directory = "/var/lib/clamav";
          user = "clamav";
          group = "clamav";
          mode = "0700";
        }
        {
          directory = "/var/log/clamav";
          user = "clamav";
          group = "clamav";
          mode = "0700";
        }
      ]
      ++
        optionals (cfg.scan.on-access.enable || cfg.scan.on-modify.enable || cfg.scan.on-schedule.enable)
          [
            {
              directory = cfg.quarantineDirectory;
              user = "root";
              group = "root";
              mode = "0700";
            }
          ];
  };
}
