# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ghaf.partitioning.verity;
  debugEnable = config.ghaf.profiles.debug.enable;
in
{
  options.ghaf.partitioning.verity = {
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
        # TODO: switch to -zzstd when kernel >= 6.10 (better compression & decompression speed)
        # Experimental high-performance patch for `mkfs.erofs`
        # FIXME: Question for review -- move to overlays, vendor patch
        erofs-utils-nix = pkgs.buildPackages.erofs-utils.overrideAttrs (_: {
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
            -zlz4hc,9 -T 1 --all-root \
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

          # Create UKI kernel with embedded verityhash
          sed -E "s/^(Cmdline=.*)/\1 ghaf.storehash=$verityRoothash/" \
            ${config.boot.uki.configFile} >ukify-verity.conf
          ${pkgs.buildPackages.systemdUkify}/lib/systemd/ukify build \
            --config=ukify-verity.conf \
            --output="kernel.efi"
          # ${kernelImage} don't work for some reasons, so move kernel in place
          mv kernel.efi ${kernelImage}

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

    # Show pretty name in bootloader
    system.nixos.extraOSReleaseArgs = {
      PRETTY_NAME = "Ghaf ${config.ghaf.version}"; # FIXME: Probably too global override
    };
    boot = {
      kernelParams = [
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
