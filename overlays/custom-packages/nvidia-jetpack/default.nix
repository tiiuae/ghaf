{ final, prev }:
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
let
  signedArtifactsExtractor = prev.extractSignedOrinArtifacts;
  wrappedFlashScript = final.writeShellApplication {
    name = "initrd-flash-ghaf-host";
    runtimeInputs = [
      final.coreutils
      signedArtifactsExtractor
    ];
    text = ''
            #!/usr/bin/env bash
            set -euo pipefail

            usage() {
              cat <<'USAGE'
      Usage: initrd-flash-ghaf-host [options] [-s <signed-sd-image>]

        -s, --signed-sd-image DIR   Path to the signed sd-image result in the Nix store.
                                    When provided, signed boot artifacts are automatically
                                    extracted before flashing.
        -h, --help                  Show this help and exit.

      All other arguments are forwarded to NVIDIA's flashing script verbatim.
      USAGE
            }

            signed_sd_image=""

            while [[ $# -gt 0 ]]; do
              case "$1" in
                -s|--signed-sd-image)
                  if [[ $# -lt 2 ]]; then
                    echo "Missing argument for $1" >&2
                    usage
                    exit 1
                  fi
                  signed_sd_image="$2"
                  shift 2
                  ;;
                -h|--help)
                  usage
                  exit 0
                  ;;
                --)
                  shift
                  break
                  ;;
                *)
                  break
                  ;;
              esac
            done

            temp_signed_dir=""
            cleanup() {
              if [[ -n "$temp_signed_dir" && -d "$temp_signed_dir" ]]; then
                rm -rf "$temp_signed_dir"
              fi
            }

            if [[ -n "$signed_sd_image" ]]; then
              if [[ ! -d "$signed_sd_image" ]]; then
                echo "Signed image directory not found: $signed_sd_image" >&2
                exit 1
              fi
              temp_signed_dir=$(mktemp -d)
              trap cleanup EXIT
              ${signedArtifactsExtractor}/bin/extract-signed-orin-artifacts \
                --sd-image-dir "$signed_sd_image" \
                --output "$temp_signed_dir" \
                --force >/dev/null
              export SIGNED_ARTIFACTS_DIR="$temp_signed_dir"
            fi

            "${prev.nvidia-jetpack.flashScript}/bin/initrd-flash-ghaf-host" "$@"
            status=$?
            cleanup
            exit $status
    '';
  };
in
prev.nvidia-jetpack
// {
  flashScript = wrappedFlashScript;
}
