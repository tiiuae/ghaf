# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  findutils,
  jq,
  runCommand,
  writeShellApplication,
}:
let
  ghaf-secure-ab-config = writeShellApplication {
    name = "ghaf-secure-ab-config";
    runtimeInputs = [
      coreutils
      findutils
      jq
    ];
    text = builtins.readFile ./ghaf-secure-ab-config.sh;
    meta = {
      description = "Export public-only Ghaf secure A/B build configuration";
      mainProgram = "ghaf-secure-ab-config";
    };
  };
in
ghaf-secure-ab-config.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.smoke =
      runCommand "ghaf-secure-ab-config-smoke"
        {
          nativeBuildInputs = [
            findutils
            ghaf-secure-ab-config
            jq
          ];
        }
        ''
          mkdir keys
          for file in PK.crt KEK.crt db.crt update.pub; do
            printf '%s\n' "$file" > "keys/$file"
          done
          printf 'private\n' > keys/db.key

          ghaf-secure-ab-config --key-dir keys --generation 8 --output exported
          test "$(jq -r .schema_version exported/config.json)" = 1
          test "$(jq -r .trust exported/config.json)" = external
          test "$(jq -r .generation exported/config.json)" = 8
          test "$(jq -r .inject_boot_health_failure exported/config.json)" = false
          test ! -e exported/db.key
          test "$(find exported -mindepth 1 -maxdepth 1 -type f | wc -l)" = 5
          ! ghaf-secure-ab-config --key-dir keys --generation 8 --output exported
          ! ghaf-secure-ab-config --key-dir keys --generation 0 --output invalid

          ghaf-secure-ab-config --key-dir keys --generation 9 \
            --output failure-injection --inject-boot-health-failure
          test "$(jq -r .inject_boot_health_failure failure-injection/config.json)" = true
          touch "$out"
        '';
  };
})
