# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;
  inherit (pkgs.stdenv.hostPlatform) efiArch;
in
{
  _file = ./verity-repart.nix;

  config = lib.mkIf cfg.enable {
    image.repart = {
      name = "ghaf";
      inherit (cfg) version;

      partitions = {
        "00-esp" = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
          repartConfig = {
            Type = "esp";
            Format = "vfat";
            SizeMinBytes = "64M";
            UUID = "null";
          };
        };

        # Verity tree for the Nix store.
        "10-root-verity-a" = {
          repartConfig = {
            Type = "root-verity";
            Label = "root-verity-a";
            Verity = "hash";
            VerityMatchKey = "root";
            Minimize = "best";
          };
        };

        # Nix store.
        "11-root-a" = {
          storePaths = [ config.system.build.toplevel ];
          repartConfig = {
            Type = "root";
            Label = "root-a";
            Format = "erofs";
            Minimize = "best";
            Verity = "data";
            VerityMatchKey = "root";
            # Create directories needed for nixos activation, as these cannot be
            # created on a read-only filesystem.
            MakeDirectories = toString [
              "/bin"
              "/boot"
              "/dev"
              "/etc"
              "/home"
              "/lib"
              "/lib64"
              "/mnt"
              "/nix"
              "/opt"
              "/persist"
              "/proc"
              "/root"
              "/run"
              "/srv"
              "/sys"
              "/tmp"
              "/usr"
              "/var"
            ];
          };
        };

        # 'B' blank partitions — sysupdate writes here during A/B updates.
        # Type must match the A slot so sysupdate's MatchPartitionType can find them.
        "20-root-verity-b" = {
          repartConfig = {
            Type = "root-verity";
            SizeMinBytes = "64M";
            Label = "_empty";
            ReadOnly = 1;
            SplitName = "-";
            Weight = 0;
          };
        };
        "21-root-b" = {
          repartConfig = {
            Type = "root";
            SizeMinBytes = cfg.bSlotSize;
            SizeMaxBytes = cfg.bSlotSize;
            Label = "_empty";
            ReadOnly = 1;
            SplitName = "-";
            Weight = 0;
          };
        };

        # Data partition — LVM (PV/VG/LVs) is initialized on first boot by
        # verity-data-init.service.  The raw zeros compress to nearly nothing
        # with zstd, keeping the image small.
        "40-data" = {
          repartConfig = {
            Type = "linux-generic";
            Label = "data";
            UUID = "a142865b-37e4-48e1-acab-0118bfa6215f";
            SizeMinBytes = "14G";
            FactoryReset = "yes";
            # No Format — LVM is created by the first-boot initrd service
            # No Encrypt — encryption is deferred to first boot
          };
        };
      };
    };
  };
}
