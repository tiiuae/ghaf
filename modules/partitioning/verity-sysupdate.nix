# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  url = "https://github.com/tiiuae/ghaf/releases/latest/download";
  id = "ghaf";
  cfg = config.ghaf.partitioning.verity;
in
{
  _file = ./verity-sysupdate.nix;

  config = lib.mkIf cfg.sysupdate {
    # TODO: This is a placeholder for future implementation.
    systemd.sysupdate = {
      enable = true;
      reboot.enable = true;
      transfers = {
        "10-uki" = {
          Transfer = {
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = url;
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
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = url;
            MatchPattern = "${id}_@v_@u.verity";
          };
          Target = {
            Type = "partition";
            Path = "auto";
            MatchPattern = "verity-@v";
            MatchPartitionType = "root-verity";
            ReadOnly = 1;
          };
        };
        "22-root" = {
          Transfer = {
            Verify = "no";
          };
          Source = {
            Type = "url-file";
            Path = url;
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

    #  https://github.com/NixOS/nixpkgs/pull/436893
    #  https://github.com/NixOS/nixpkgs/pull/437869
    #  TODO: remove the below these changes
    # systemd.additionalUpstreamSystemUnits = [
    #   "systemd-bless-boot.service"
    #   "boot-complete.target"
    # ];
  };
}
