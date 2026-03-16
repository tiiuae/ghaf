# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  id = "ghaf";
  cfg = config.ghaf.partitioning.verity;
in
{
  _file = ./verity-sysupdate.nix;

  config = lib.mkIf cfg.sysupdate {
    # When delta updates are enabled, the delta service handles all artifacts
    # (root, verity, UKI) — disable sysupdate entirely to avoid duplication.
    systemd.sysupdate = lib.mkIf (!cfg.deltaUpdate.enable) {
      enable = true;
      reboot.enable = true;
      transfers = {
        "10-uki" = {
          Transfer = {
            ProtectVersion = "%A";
            # TODO: enable signature verification
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = cfg.updateUrl;
            MatchPattern = "${config.boot.uki.name}_@v.efi";
          };
          Target = {
            Type = "regular-file";
            Path = "/EFI/Linux";
            PathRelativeTo = "esp";
            MatchPattern = "${config.boot.uki.name}_@v+@l-@d.efi ${config.boot.uki.name}_@v+@l.efi ${config.boot.uki.name}_@v.efi";
            Mode = "0444";
            TriesLeft = 3;
            TriesDone = 0;
            InstancesMax = 2;
          };
        };
        "20-root-verity" = {
          Transfer = {
            # TODO: enable signature verification
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = cfg.updateUrl;
            MatchPattern = "${id}_@v_@u.verity";
          };
          Target = {
            Type = "partition";
            Path = "auto";
            MatchPattern = "root-verity-@v";
            MatchPartitionType = "root-verity";
            ReadOnly = 1;
          };
        };
        "22-root" = {
          Transfer = {
            # TODO: enable signature verification
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = cfg.updateUrl;
            MatchPattern = "${id}_@v_@u.root";
          };
          Target = {
            Type = "partition";
            Path = "auto";
            MatchPattern = "root-@v";
            MatchPartitionType = "root";
            ReadOnly = 1;
          };
        };
      };
    };

    # Ensure boot is only blessed after critical services are up.
    # systemd-bless-boot.service marks the current boot as good by removing
    # the tries suffix from the UKI filename, preventing rollback.
    systemd.targets.boot-complete = {
      wants = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
    };
  };
}
