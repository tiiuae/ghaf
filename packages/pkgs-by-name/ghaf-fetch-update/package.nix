# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  curl,
  jq,
  python3,
  runCommand,
  writeShellApplication,
}:
let
  ghaf-fetch-update = writeShellApplication {
    name = "ghaf-fetch-update";
    runtimeInputs = [
      coreutils
      curl
      jq
    ];
    text = ''
      set -euo pipefail

      usage() {
        echo "Usage: ghaf-fetch-update HTTP_ORIGIN GENERATION [FETCH_PARENT]" >&2
        exit 2
      }

      [[ $# -ge 2 && $# -le 3 ]] || usage
      update_http_origin="''${1%/}"
      generation="$2"
      fetch_parent="''${3:-/persist/sysupdate}"

      case "$update_http_origin" in
        http://?*) ;;
        *)
          echo "HTTP_ORIGIN must use http://; use ota-update registry pull for authenticated HTTPS transport" >&2
          exit 2
          ;;
      esac
      [[ "$generation" =~ ^[1-9][0-9]*$ ]] || {
        echo "GENERATION must be a positive decimal integer" >&2
        exit 2
      }

      final_dir="$fetch_parent/http-generation-$generation"
      test ! -e "$final_dir" || {
        echo "Refusing to reuse published fetch directory: $final_dir" >&2
        exit 1
      }

      fetch_dir="$(mktemp -d "$fetch_parent/.http-generation-$generation.XXXXXX")"
      chmod 0755 "$fetch_dir"

      fetch_file() {
        file="$1"
        case "$file" in
          "" | .* | *[!A-Za-z0-9._-]*)
            echo "Unsafe update file name: $file" >&2
            return 1
            ;;
        esac
        curl --fail --show-error --location \
          --proto '=http' --proto-redir '=http' \
          --retry 3 --retry-all-errors \
          --output "$fetch_dir/$file.part" \
          "$update_http_origin/$file"
        mv -- "$fetch_dir/$file.part" "$fetch_dir/$file"
      }

      fetch_file manifest.json
      fetch_file manifest.json.sig

      for kind in root verity kernel; do
        artifact="$(jq -er --arg kind "$kind" '.[$kind].file' "$fetch_dir/manifest.json")"
        fetch_file "$artifact"
      done

      touch "$fetch_dir/fetch.complete"
      sync "$fetch_dir"
      mv -T -- "$fetch_dir" "$final_dir"
      sync "$fetch_parent"

      echo "Fetched update into $final_dir"
    '';
    meta = {
      description = "Fetch a development Ghaf update bundle over HTTP";
      mainProgram = "ghaf-fetch-update";
    };
  };
in
ghaf-fetch-update.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.smoke =
      runCommand "ghaf-fetch-update-smoke"
        {
          nativeBuildInputs = [
            ghaf-fetch-update
            python3
          ];
        }
        ''
          mkdir -p server destination
          printf payload > server/root.raw.zst
          printf verity > server/verity.raw.zst
          printf kernel > server/kernel.efi
          printf signature > server/manifest.json.sig
          cat > server/manifest.json <<'EOF'
          {
            "root": { "file": "root.raw.zst" },
            "verity": { "file": "verity.raw.zst" },
            "kernel": { "file": "kernel.efi" }
          }
          EOF

          (cd server && python -m http.server 18080 --bind 127.0.0.1 > ../server.log 2>&1) &
          server_pid=$!
          trap 'kill "$server_pid" 2>/dev/null || true' EXIT

          ghaf-fetch-update http://127.0.0.1:18080 7 destination
          test -f destination/http-generation-7/fetch.complete
          test "$(cat destination/http-generation-7/root.raw.zst)" = payload
          ! ghaf-fetch-update http://127.0.0.1:18080 7 destination
          ! ghaf-fetch-update https://127.0.0.1:18080 8 destination
          ! ghaf-fetch-update http://127.0.0.1:18080 ../8 destination
          touch "$out"
        '';
  };
})
