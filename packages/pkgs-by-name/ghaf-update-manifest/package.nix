# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  jq,
  python3,
  runCommand,
  writeShellApplication,
}:
let
  manifestTool = writeShellApplication {
    name = "ghaf-update-manifest";
    runtimeInputs = [ python3 ];
    text = ''
      exec python3 ${./ghaf-update-manifest.py} "$@"
    '';
    meta = {
      description = "Generate and rehash Ghaf secure update manifests";
      mainProgram = "ghaf-update-manifest";
    };
  };
in
manifestTool.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.roundtrip =
      runCommand "ghaf-update-manifest-roundtrip"
        {
          nativeBuildInputs = [
            manifestTool
            jq
          ];
        }
        ''
          printf '%064d\n' 0 > hash
          for kind in root verity kernel; do printf '%s' "$kind" > "$kind-@v-@u"; done
          ghaf-update-manifest generate --version 1 --system aarch64-linux \
            --build-system x86_64-linux --target test --generation 8 --hash-file hash \
            --root-image root-@v-@u --verity-image verity-@v-@u \
            --kernel-image kernel-@v-@u --root-unpacked-size 4 --verity-unpacked-size 6 \
            --manifest manifest.json
          ghaf-update-manifest validate --manifest manifest.json
          cp manifest.json original.json
          ghaf-update-manifest rehash --manifest manifest.json
          cmp original.json manifest.json
          kernel=$(jq -r .kernel.file manifest.json)
          printf signed >> "$kernel"
          ghaf-update-manifest rehash --manifest manifest.json
          test "$(jq -r .kernel.sha256 manifest.json)" = "$(sha256sum "$kernel" | cut -d' ' -f1)"
          test "$(jq -r .kernel.unpacked_size manifest.json)" -eq 12

          for invalid in \
            '.generation = true' \
            '."build-system" = null' \
            '.root.unpacked_size = 0' \
            '.root.unpacked_size = true' \
            '.root.file = "../root"' \
            '.root.file = .kernel.file' \
            '.root.file = "invalid.json"' \
            '.kernel.file = "invalid.json.sig"'; do
            jq "$invalid" original.json > invalid.json
            cp invalid.json before.json
            for command in validate rehash; do
              if ghaf-update-manifest "$command" --manifest invalid.json 2>error.log; then
                echo "Unexpectedly accepted: $invalid ($command)" >&2
                exit 1
              fi
              grep -q 'ValueError:' error.log
            done
            cmp before.json invalid.json
          done
          touch "$out"
        '';
  };
})
