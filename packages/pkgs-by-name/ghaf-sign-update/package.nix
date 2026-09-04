# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  ghaf-update-manifest,
  jq,
  openssl,
  runCommand,
  sbsigntool,
  writeShellApplication,
}:
let
  ghaf-sign-update = writeShellApplication {
    name = "ghaf-sign-update";
    runtimeInputs = [
      coreutils
      ghaf-update-manifest
      jq
      openssl
      sbsigntool
    ];
    text = builtins.readFile ./ghaf-sign-update.sh;
    meta.description = "Sign a Ghaf update UKI and detached manifest outside the Nix store";
  };
in
ghaf-sign-update.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.reject-name-collision =
      runCommand "ghaf-sign-update-reject-name-collision"
        {
          nativeBuildInputs = [
            coreutils
            ghaf-sign-update
            openssl
          ];
        }
        ''
          mkdir keys input output
          openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes \
            -subj /CN=test/ -days 1 -keyout keys/db.key -out keys/db.crt >/dev/null 2>&1
          openssl genpkey -algorithm ED25519 -out keys/update.key
          openssl pkey -in keys/update.key -pubout -outform DER -out keys/update.pub.der
          tail -c 32 keys/update.pub.der > keys/update.pub

          cat > input/manifest.json <<'EOF'
          {
            "manifest_version": 2,
            "system": "test-system",
            "target": "test-target",
            "generation": 1,
            "root_verity_hash": "0000000000000000000000000000000000000000000000000000000000000000",
            "root": { "file": "manifest.json" },
            "verity": { "file": "verity.raw.zst" },
            "kernel": { "file": "kernel.efi" }
          }
          EOF
          before="$(sha256sum input/manifest.json)"
          ! ghaf-sign-update --key-dir keys --input input/manifest.json --output output \
            2>error.log
          grep -F "Artifact file names must be distinct" error.log
          test "$(sha256sum input/manifest.json)" = "$before"
          touch "$out"
        '';
  };
})
