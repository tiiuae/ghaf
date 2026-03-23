# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Host-specific ClamAV configuration
#
# Only contains host-specific tmpfiles rules for persistent storage.
# All services run on both host and VMs (configured in default.nix).
#
{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.ghaf.security.clamav;
  isHost = options.ghaf.virtualization ? microvm-host;
in
{
  _file = ./host.nix;

  config = lib.mkIf (cfg.enable && isHost) {
    systemd.tmpfiles.rules = [
      "d /var/lib/clamav 0700 clamav clamav -"
      "d /var/log/clamav 0700 clamav clamav -"
      "f /var/log/clamav/clamd.log 0600 clamav clamav -"
    ]
    ++ lib.optional (
      cfg.scan.on-access.enable || cfg.scan.on-modify.enable || cfg.scan.on-schedule.enable
    ) "d ${cfg.quarantineDirectory} 0700 clamav clamav -";
  };
}
