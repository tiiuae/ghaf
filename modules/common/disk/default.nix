{
  config,
  lib,
  pkgs,
  ...
}:

{

  imports = [
    ./update.nix
    ./image.nix
  ];

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

  nixpkgs.config.allowUnfree = true;

  # For debugging
  ghaf.systemd.withDebug = true;

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
          "/var"
          "/etc"
          "/bin" # /bin/sh symlink needs to be created
          "/usr" # /usr/bin/env symlink needs to be created
          "/tmp"
          "/home"
          "/root"
        ]
    );

}
