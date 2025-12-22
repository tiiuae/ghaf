# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # FIXME: naming -- ghaf.partitioning vs ghaf.partitions
  cfg = config.ghaf.partitioning.verity;
  inherit (config.ghaf.partitions) definition;
  inherit (pkgs.stdenv.hostPlatform) efiArch;
  repartConfig = lib.mapAttrs (_name: value: {
    repartConfig = value;
  }) config.systemd.repart.partitions;
in
{

  config = lib.mkIf cfg.enable {
    image.repart = {
      name = "ghaf";
      version = "0.0.1";

      partitions = repartConfig // {
        # Overwrite esp and root
        "00-esp" = {
          contents = {
            "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
              "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

            "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
              "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
          };
          # FIXME: move to repart-common
          repartConfig = {
            Type = "esp";
            Format = definition.esp.fileSystem;
            SizeMinBytes = definition.esp.size;
            # FIXME: why null? ESP have standard UUID value
            UUID = "null";
          };
        };

        # Verity tree for the Nix store.
        "11-root-verity-a" = {
          repartConfig = config.systemd.repart.partitions."11-root-verity-a" // {
            Minimize = "best";
          };
        };

        # Nix store.
        "10-root-a" = {
          # FIXME: This require HUGE amount of space in /var/nix/builds
          # FIXME: Make erofs as separate artifact
          storePaths = [ config.system.build.toplevel ];
          repartConfig = config.systemd.repart.partitions."10-root-a" // {
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
      };
    };
  };
}
