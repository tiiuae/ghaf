# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:

let
  roothashPlaceholder = "61fe0f0c98eff2a595dd2f63a5e481a0a25387261fa9e34c37e3a4910edf32b8";
  cfg = config.ghaf.partitioning.verity-volume;
  debugEnable = config.ghaf.profiles.debug.enable;
in
{
  options.ghaf.partitioning.verity-volume = {
    enable = lib.mkEnableOption "the verity (image-based) partitioning scheme";
  };

  imports = [
    # FIXME: ghaf-veritysetup-generator here!
  ];

  config = lib.mkIf cfg.enable {
    system.build.ghafImage =
      let
        inherit (config.ghaf) version;
        id = "ghaf";
        fsImage = "$out/${id}_root_@v_@u.raw";
        verityImage = "$out/${id}_verity_@v_@u.raw";
        kernelImage = "$out/${id}_kernel_@v_@u.efi";
        mkfsCommand = "mkfs.erofs -T 1 --all-root -L nix-store --mount-point=/nix/store ${fsImage} --hard-dereference --tar=f";
        regInfo = pkgs.closureInfo {
          rootPaths = [ config.system.build.toplevel ];
        };
      in
      pkgs.runCommandLocal "ghaf-sysupdate-image"
        {
          nativeBuildInputs = [
            pkgs.buildPackages.time
            pkgs.buildPackages.gnutar
            pkgs.buildPackages.erofs-utils
            pkgs.buildPackages.cryptsetup
          ];
          passthru = {
            inherit regInfo;
          };
          __structuredAttrs = true;
          unsafeDiscardReferences.out = true;
        }
        ''
          mkdir $out
          echo Creating a store image
          tar --create \
            --absolute-names \
            --verbatim-files-from \
            --transform 'flags=rSh;s|/nix/store/||' \
            --transform 'flags=rSh;s|~nix~case~hack~[[:digit:]]\+||g' \
            --files-from ${regInfo}/store-paths \
            | time ${mkfsCommand}

          # Align file to block boundary
          truncate -s %4096 ${fsImage}

          echo Creating verity image
          time veritysetup format --root-hash-file $out/dm-verity-root-hash ${fsImage} ${verityImage}
          # Align file to block boundary
          truncate -s %4096 ${verityImage}

          cp ${config.system.build.uki}/${config.system.boot.loader.ukiFile} ${kernelImage}

          # Replace the placeholder with the real roothash in the target .raw file
          verityRoothash=$(cat $out/dm-verity-root-hash)
          sed -i \
            "0,/${roothashPlaceholder}/ s/${roothashPlaceholder}/$verityRoothash/" \
            ${kernelImage}

          # Compress the image
          ${pkgs.buildPackages.zstd}/bin/zstd --compress $out/*raw
          rm -f $out/*raw

          # Inject hash fragment into file names and create manifest for `ota-update`
          # (see ./inject-uuids.py for implementation details)
          ${pkgs.buildPackages.python3}/bin/python ${./mk-manifest.py} ${version} $out/dm-verity-root-hash ${fsImage}.zst ${verityImage}.zst ${kernelImage} $out/${id}_@v_@u.manifest

          # Clean-up
          rm -f $out/dm-verity-root-hash
        '';

    ghaf.graphics.boot.enable = lib.mkForce (!debugEnable); # FIXME: temporary

    # FIXME: Remove overlay when/if https://github.com/NixOS/nixpkgs/pull/468940 merged
    # FIXME: switch to own custom fork, which support volumes instead of partitions
    nixpkgs.overlays = [
      (_final: prev: {
        # nix-store-veritysetup-generator should be built against same systemd that used in initrd
        # FIXME: upstream it!
        nix-store-veritysetup-generator = prev.nix-store-veritysetup-generator.override {
          systemd = config.boot.initrd.systemd.package;
        };
      })
    ];

    boot = {
      kernelParams = [
        "storehash=${roothashPlaceholder}" # See `nix-store-veritysetup.enable` for details
        "systemd.verity_root_options=panic-on-corruption"
        "ghaf.revision=${config.ghaf.version}" # Help ghaf-veritysetup-generator to find root and verity volumes
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
        # nix-store-veritysetup.enable = true; # FIXME: put back our forked version

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

    fileSystems = {
      "/" = {
        device = "none";
        fsType = "tmpfs";
        options = [
          "size=10%"
          "mode=755"
        ];
      };
      "/nix/store" = {
        fsType = "erofs";
        # for systemd-remount-fs
        options = [ "ro" ];
        device = "/dev/mapper/nix-store"; # volume name `nix-store` hardcoded in `nix-store-veritysetup-generator`
      };
    };
  };
}
