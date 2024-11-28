# Copyright 2025 TII (SSRC) and the Ghaf contributors
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
in
{
  options.ghaf.partitioning.verity = {
    split = lib.mkOption {
      description = "Whether to split the partitions to separate files instead of a single image";
      type = lib.types.bool;
      default = false;
    };
  };

  imports = [
    "${modulesPath}/image/repart.nix"
    "${modulesPath}/system/boot/uki.nix"
  ];

  config = {

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
      '';
    });

    boot.kernelParams = [
      "roothash=${roothashPlaceholder}"
    ];

    # TODO remove these
    boot.initrd.systemd.initrdBin = [
      pkgs.less
      pkgs.util-linux
    ];
    ghaf.systemd.withDebug = true;
    nixpkgs.config.allowUnfree = true;
    # TODO end

    image.repart.split = cfg.split;

    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.initrd.systemd = {
      enable = true;
      dmVerity.enable = true;
    };

    boot.initrd.compressor = "zstd";
    boot.initrd.compressorArgs = [ "-6" ];
    environment.systemPackages = with pkgs; [
      cryptsetup
    ];

    # System is now immutable
    system.switch.enable = false;

    # For some reason this needs to be true
    users.mutableUsers = lib.mkForce true;

    services.getty.autologinUser = "root";

    boot.initrd.supportedFilesystems = {
      btrfs = true;
      erofs = true;
    };

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
            device = "/dev/disk/by-partuuid/${partConf.UUID}";
            fsType = partConf.Format;
          };
      }
      // builtins.listToAttrs (
        builtins.map
          (path: {
            name = path;
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
