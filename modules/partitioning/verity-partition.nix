# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  roothashPlaceholder = "61fe0f0c98eff2a595dd2f63a5e481a0a25387261fa9e34c37e3a4910edf32b8";
  cfg = config.ghaf.partitioning.verity;
  debugEnable = config.ghaf.profiles.debug.enable;
in
{
  _file = ./verity-partition.nix;

  options.ghaf.partitioning.verity = {
    enable = lib.mkEnableOption "the verity (image-based) partitioning scheme";

    split = lib.mkOption {
      description = "Whether to split the partitions to separate files instead of a single image";
      type = lib.types.bool;
      default = false;
    };

    sysupdate = lib.mkOption {
      description = "Enable systemd sysupdate";
      type = lib.types.bool;
      default = false;
    };
  };

  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/system/boot/uki.nix"
  ];

  config = lib.mkIf cfg.enable {
    ghaf.partitioning.btrfs-postboot.enable = true;

    ghaf.storage.encryption.partitionDevice = lib.mkDefault "/dev/disk/by-partuuid/${
      config.image.repart.partitions."50-persist".repartConfig.UUID
    }";

    system.build.ghafImage = config.system.build.image.overrideAttrs (oldAttrs: {
      nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.jq ];
      postInstall = ''
        # Extract the roothash from the JSON
        repartRoothash="$(
          ${lib.getExe pkgs.jq} -r \
            '[.[] | select(.roothash != null)] | .[0].roothash' \
            "$out/repart-output.json"
        )"

        # Replace the placeholder with the real roothash in the target .raw file
        sed -i \
          "0,/${roothashPlaceholder}/ s/${roothashPlaceholder}/$repartRoothash/" \
          "$out/${oldAttrs.pname}_${oldAttrs.version}.raw"

        # Compress the image
        ${pkgs.zstd}/bin/zstd --compress $out/*raw
        rm $out/*raw
      '';
    });

    image.repart.split = cfg.split;

    boot = {
      kernelParams = [
        "roothash=${roothashPlaceholder}"
        "systemd.verity_root_options=panic-on-corruption"
      ]
      ++ lib.optional debugEnable "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1";

      # No bootloaders needed yet
      loader = {
        grub.enable = false;
        systemd-boot.enable = lib.mkForce false;
      };

      # Enable dm-verity and compress initrd
      initrd = {
        systemd = {
          enable = true;
          dmVerity.enable = true;
        };

        compressor = "zstd";
        compressorArgs = [ "-6" ];

        supportedFilesystems = {
          btrfs = true;
          erofs = true;
        };
      };
    };

    environment.systemPackages = with pkgs; [
      cryptsetup
    ];

    # Enable systemd features
    ghaf.systemd = {
      withRepart = true;
      withSysupdate = true;
    };

    # System is now immutable
    system.switch.enable = false;

    swapDevices = [
      {
        device =
          if config.ghaf.storage.encryption.enable then "/dev/mapper/swap" else "/dev/disk/by-partlabel/swap";
        discardPolicy = "both";
        options = [ "nofail" ];
      }
    ];

    fileSystems =
      let
        tmpfsConfig = {
          neededForBoot = true;
          fsType = "tmpfs";
        };
      in
      {
        "/" = {
          fsType = "erofs";
          # for systemd-remount-fs
          options = [ "ro" ];
          device = "/dev/mapper/root";
        };

        "/persist" =
          let
            partConf = config.image.repart.partitions."50-persist".repartConfig;
          in
          {
            device =
              if config.ghaf.storage.encryption.enable then
                "/dev/mapper/persist"
              else
                "/dev/disk/by-partuuid/${partConf.UUID}";
            fsType = partConf.Format;
          };
      }
      // builtins.listToAttrs (
        map
          (pathDir: {
            name = pathDir;
            value = tmpfsConfig;
          })
          [
            "/bin" # /bin/sh symlink needs to be created
            "/etc"
            "/home"
            "/root"
            "/tmp"
            "/usr" # /usr/bin/env symlink needs to be created
            "/var"
          ]
      );
  };
}
