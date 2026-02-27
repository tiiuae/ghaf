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

  config = lib.mkIf cfg.enable {
    system.build.ghafImage =
      let
        inherit (config.ghaf) version;
        id = "ghaf";
        fsImage = "$out/${id}_root_@v_@u.raw";
        verityImage = "$out/${id}_verity_@v_@u.raw";
        kernelImage = "$out/${id}_kernel_@v_@u.efi";

        # Experimental high-performance patch for `mkfs.erofs`
        # FIXME: Question for review -- move to overlays, vendor patch
        erofs-utils-nix = pkgs.erofs-utils.overrideAttrs (_: {
          src = pkgs.fetchFromGitHub {
            owner = "avnik";
            repo = "erofs-utils";
            rev = "1f24c4d03527189d2bdab87a564cec297d1b6b9a"; # branch: avnik/ghaf
            hash = "sha256-4kCFIIqIMpz0hnewBvHCQF2OODDzH3xmRux7PPWdJJ4=";
          };
        });
        regInfo = pkgs.closureInfo {
          rootPaths = [ config.system.build.toplevel ];
        };
      in
      pkgs.runCommandLocal "ghaf-sysupdate-image"
        {
          nativeBuildInputs = [
            pkgs.buildPackages.time
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

          mkfsWorkers="''${NIX_BUILD_CORES:-1}"
          if [ "$mkfsWorkers" -gt 8 ]; then
            mkfsWorkers=8
          fi

          time ${erofs-utils-nix}/bin/mkfs.erofs \
            -T 1 --all-root \
            --workers="$mkfsWorkers" \
            -L nix-store \
            ${fsImage} \
            --hard-dereference \
            --nix-closure "${regInfo}/store-paths";

          # Align file to block boundary
          truncate -s %4096 ${fsImage}

          echo Creating verity image
          time veritysetup format --root-hash-file $out/dm-verity-root-hash ${fsImage} ${verityImage}
          # Align file to block boundary
          truncate -s %4096 ${verityImage}

          cp ${config.system.build.uki}/${config.system.boot.loader.ukiFile} ${kernelImage}

          # Replace the placeholder with the real roothash in the target .raw file
          verityRoothash=$(cat $out/dm-verity-root-hash)

          # SAFETY: root hash later validated in mk-manifest.py
          test -n "$verityRoothash" || (echo "bad root hash" >&2 && exit 1)

          # FIXME: Call `ukify` directly and avoid sed/placeholder hack
          sed -i \
            "0,/${roothashPlaceholder}/ s/${roothashPlaceholder}/$verityRoothash/" \
            ${kernelImage}

          # FIXME: move compression into mk-manifest.py and compute unpacked sizes there.
          rootUnpackedSize=$(stat -c%s ${fsImage})
          verityUnpackedSize=$(stat -c%s ${verityImage})

          # Compress the image
          ${pkgs.buildPackages.zstd}/bin/zstd --compress $out/*raw
          rm -f $out/*raw

          # Create artifacts and manifest.
          ${pkgs.buildPackages.python3}/bin/python ${./mk-manifest.py} \
            --version ${version} \
            --system ${config.nixpkgs.hostPlatform.system} \
            --hash-file $out/dm-verity-root-hash \
            --root-image ${fsImage}.zst \
            --verity-image ${verityImage}.zst \
            --kernel-image ${kernelImage} \
            --manifest $out/${id}_@v_@u.manifest \
            --root-unpacked-size "$rootUnpackedSize" \
            --verity-unpacked-size "$verityUnpackedSize"

          # Clean-up
          rm -f $out/dm-verity-root-hash
        '';

    ghaf.graphics.boot.enable = lib.mkForce (!debugEnable); # FIXME: temporary

    # Show pretty name in bootloader
    system.nixos.extraOSReleaseArgs = {
      PRETTY_NAME = "Ghaf ${config.ghaf.version}"; # FIXME: Probably too global override
    };
    boot = {
      kernelParams = [
        "ghaf.storehash=${roothashPlaceholder}" # See `ghaf-store-veritysetup.enable` for details
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
          ghaf-store-veritysetup-generator.enable = true;
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

    # System is now immutable
    system.switch.enable = false;

    fileSystems = {
      "/" = lib.mkForce {
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
