# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared directories options definitions
#
{ lib, ... }:
{
  options.ghaf.storage.shared-directories = {

    enable = lib.mkEnableOption "shared directories module for cross-VM file sharing";
    debug = lib.mkEnableOption "debug logging for shared directories daemon";

    scanner = {
      enable = lib.mkEnableOption ''
        malware scanning. This option is a global scanning override, so no malware scanning will
        be performed, irrespective of whether the individual channel scanning option is enabled or not.

        Note: when this option is enabled, you need to make sure that the scanning daemon is
        running at the time when shares are used - otherwise, any content will be treated as malware.
        You can bypass this behaviour per-channel by enabling the `permissive` option, which will
        gracefully ignore scanning daemon errors and only trigger on infected files
      '';
    };

    baseDirectory = lib.mkOption {
      type = lib.types.path;
      default = "/persist/shared";
      description = "Base directory where shared directory channels will be created";
    };

    channels = lib.mkOption {
      type = lib.types.attrsOf lib.dataChannel;
      default = { };
      description = ''
        Shared directory channels for cross-VM file sharing.

        Each channel has a mode:
        - `untrusted`: Per-writer isolation with scanning enabled by default
        - `trusted`: Per-writer isolation with scanning disabled by default
        - `fallback`: Simple shared directory on host, participants access via their mountpoint (no isolation, no scanning)

        For untrusted/trusted modes, the daemon monitors changes and distributes files
        to all readWrite and readOnly participants. If scanning.enable = true, files
        are scanned before distribution.

        Participants:
        - readWrite: Can read and write; content is synced between all readWrite participants
        - readOnly: Can only read the aggregated content from all writers
        - writeOnly: Can write but cannot see content from other participants (diode mode)
      '';
    };
  };
}
