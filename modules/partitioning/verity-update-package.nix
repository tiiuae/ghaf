# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Produces a set of OTA update artifacts from the split repart output:
#   - ghaf_<version>_<uuid>.root    (EROFS root filesystem)
#   - ghaf_<version>_<uuid>.verity  (dm-verity hash tree)
#   - <uki-name>_<version>.efi      (UKI with correct roothash)
#   - SHA256SUMS
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;
  delta = cfg.deltaUpdate;
  roothashPlaceholder = "61fe0f0c98eff2a595dd2f63a5e481a0a25387261fa9e34c37e3a4910edf32b8";
  id = "ghaf";
  ukiName = config.boot.uki.name;
in
{
  _file = ./verity-update-package.nix;

  config = lib.mkIf (cfg.enable && cfg.split) {
    system.build.updatePackage = config.system.build.image.overrideAttrs (oldAttrs: {
      pname = "${oldAttrs.pname}-update";

      nativeBuildInputs =
        oldAttrs.nativeBuildInputs
        ++ [
          pkgs.jq
        ]
        ++ lib.optional delta.enable pkgs.desync;

      postInstall = ''
        ${oldAttrs.postInstall or ""}

        updateDir="$out/update"
        mkdir -p "$updateDir"

        # Extract the roothash from repart output
        roothash="$(
          ${lib.getExe pkgs.jq} -r \
            '[.[] | select(.roothash != null)] | .[0].roothash' \
            "$out/repart-output.json"
        )"

        if [ -z "$roothash" ] || [ "$roothash" = "null" ]; then
          echo "ERROR: could not extract roothash from repart-output.json" >&2
          exit 1
        fi
        echo "Extracted roothash: $roothash"

        # Extract partition UUIDs for root and root-verity from repart output.
        # The UUID is needed in the sysupdate artifact filename.
        rootUuid="$(
          ${lib.getExe pkgs.jq} -r \
            '[.[] | select(.type == "root" and .label != "_empty")] | .[0].uuid' \
            "$out/repart-output.json"
        )"
        verityUuid="$(
          ${lib.getExe pkgs.jq} -r \
            '[.[] | select(.type == "root-verity" and .label != "_empty")] | .[0].uuid' \
            "$out/repart-output.json"
        )"

        echo "Root UUID: $rootUuid"
        echo "Verity UUID: $verityUuid"

        # Find and rename split partition files.
        # systemd-repart split output uses the partition type as suffix.
        for f in "$out"/*.root.raw; do
          [ -f "$f" ] && cp "$f" "$updateDir/${id}_${cfg.version}_''${rootUuid//-/_}.root"
        done
        for f in "$out"/*.root-verity.raw; do
          [ -f "$f" ] && cp "$f" "$updateDir/${id}_${cfg.version}_''${verityUuid//-/_}.verity"
        done

        # Build the UKI with the real roothash injected.
        # Copy the UKI from the build and replace the placeholder roothash.
        cp "${config.system.build.uki}/${config.system.boot.loader.ukiFile}" \
          "$updateDir/${ukiName}_${cfg.version}.efi"
        sed -i \
          "0,/${roothashPlaceholder}/ s/${roothashPlaceholder}/$roothash/" \
          "$updateDir/${ukiName}_${cfg.version}.efi"

        ${lib.optionalString delta.enable ''
            # --- Delta update artifacts ---
            # Produce a caibx index + content-addressed chunk store from the root image.
            # The chunk store can be merged with previous versions on the server so
            # devices only download blocks that actually changed.
            rootImage="$updateDir/${id}_${cfg.version}_''${rootUuid//-/_}.root"
            caibxFile="$updateDir/${id}_${cfg.version}_''${rootUuid//-/_}.caibx"

            # Capture root image size before chunking (needed for manifest)
            rootSize="$(stat -c%s "$rootImage")"

            mkdir -p "$out/chunks"
            desync --digest sha256 make \
              --store "$out/chunks" \
              --chunk-size ${delta.chunkSize} \
              "$caibxFile" \
              "$rootImage"

            echo "Chunk store statistics:"
            echo "  Chunks: $(find "$out/chunks" -type f | wc -l)"
            echo "  Total size: $(du -sh "$out/chunks" | cut -f1)"

            # Remove the full root image — only the caibx + chunks are needed for delta delivery
            rm "$rootImage"

            # Compute SHA256 of root image from the caibx (for manifest)
            rootSha256="$(sha256sum "$caibxFile" | cut -d' ' -f1)"
            veritySha256="$(sha256sum "$updateDir/${id}_${cfg.version}_''${verityUuid//-/_}.verity" | cut -d' ' -f1)"
            ukiSha256="$(sha256sum "$updateDir/${ukiName}_${cfg.version}.efi" | cut -d' ' -f1)"

            # Generate machine-readable manifest for the delta update service
            cat > "$updateDir/manifest.json" <<MANIFEST
          {
            "version": "${cfg.version}",
            "root": {
              "caibx": "${id}_${cfg.version}_''${rootUuid//-/_}.caibx",
              "size": $rootSize,
              "sha256": "$rootSha256"
            },
            "verity": {
              "file": "${id}_${cfg.version}_''${verityUuid//-/_}.verity",
              "sha256": "$veritySha256"
            },
            "uki": {
              "file": "${ukiName}_${cfg.version}.efi",
              "sha256": "$ukiSha256"
            }
          }
          MANIFEST

            echo "Generated manifest.json:"
            cat "$updateDir/manifest.json"
        ''}

        # Generate checksums
        (cd "$updateDir" && sha256sum -- * > SHA256SUMS)

        echo "Update package contents:"
        ls -la "$updateDir"
      '';
    });
  };
}
