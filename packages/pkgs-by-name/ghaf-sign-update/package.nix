# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  ghaf-dev-keygen,
  ghaf-update-manifest,
  jq,
  openssl,
  runCommand,
  sbsigntool,
  systemd,
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
    tests.verify-input =
      runCommand "ghaf-sign-update-verify-input"
        {
          nativeBuildInputs = [
            ghaf-dev-keygen
            ghaf-sign-update
            ghaf-update-manifest
            jq
            openssl
            sbsigntool
          ];
        }
        ''
          ghaf-dev-keygen --output keys
          mkdir input
          printf root > input/root.raw
          printf verity > input/verity.raw
          cp ${systemd}/lib/systemd/boot/efi/systemd-boot*.efi input/kernel.efi
          printf '%064d\n' 0 > hash
          ghaf-update-manifest generate --version 1 --system test-system \
            --build-system test-system --target test-target --generation 1 \
            --hash-file hash --root-image input/root.raw --root-unpacked-size 4 \
            --verity-image input/verity.raw --verity-unpacked-size 6 \
            --kernel-image input/kernel.efi --manifest input/manifest.json
          sha256sum input/* > original.sha256

          ghaf-sign-update --key-dir keys --input input/manifest.json --output signed
          sha256sum --check original.sha256
          cmp input/root.raw signed/root.raw
          cmp input/verity.raw signed/verity.raw
          sbverify --cert keys/db.crt signed/kernel.efi
          openssl pkey -in keys/update.key -pubout -out update.pem
          openssl pkeyutl -verify -rawin -pubin -inkey update.pem \
            -in signed/manifest.json -sigfile signed/manifest.json.sig
          for kind in root verity kernel; do
            file=$(jq -r ".$kind.file" signed/manifest.json)
            test "$(sha256sum "signed/$file" | cut -d' ' -f1)" = \
              "$(jq -r ".$kind.sha256" signed/manifest.json)"
          done
          test "$(jq -r '.kernel.sha256' input/manifest.json)" != \
            "$(jq -r '.kernel.sha256' signed/manifest.json)"

          for kind in root verity kernel; do
            cp -r input "tampered-$kind"
            file=$(jq -r ".$kind.file" input/manifest.json)
            chmod u+w "tampered-$kind/$file"
            printf x >> "tampered-$kind/$file"
            if ghaf-sign-update --key-dir keys --input "tampered-$kind/manifest.json" \
              --output "rejected-$kind" 2>error.log; then
              echo "Unexpectedly signed tampered $kind" >&2
              exit 1
            fi
            grep -F "$file does not match the sha256 recorded in the input manifest" error.log
            test ! -e "rejected-$kind/manifest.json.sig"
            test ! -e "rejected-$kind/kernel.efi"
          done
          touch "$out"
        '';
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
            "version": "test-version",
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
