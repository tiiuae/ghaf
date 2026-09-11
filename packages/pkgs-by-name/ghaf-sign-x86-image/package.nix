# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bmaptool,
  coreutils,
  findutils,
  gnugrep,
  gptfdisk,
  jq,
  mtools,
  openssl,
  runCommand,
  sbsigntool,
  systemd,
  util-linux,
  writeShellApplication,
  zstd,
}:
let
  signer = writeShellApplication {
    name = "ghaf-sign-x86-image";
    runtimeInputs = [
      bmaptool
      coreutils
      findutils
      gnugrep
      jq
      mtools
      openssl
      sbsigntool
      util-linux
      zstd
    ];
    text = builtins.readFile ./ghaf-sign-x86-image.sh;
    meta.description = "Sign the EFI boot chain in a Ghaf x86 disk image outside the Nix store";
  };
in
signer.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.sign =
      runCommand "ghaf-sign-x86-image-test"
        {
          nativeBuildInputs = [
            signer
            gptfdisk
            mtools
            jq
            openssl
            sbsigntool
            zstd
          ];
        }
        ''
          # Exercise real FAT and Authenticode operations without privileged devices.
          test "$(id -u)" -ne 0
          mkdir keys input
          openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes \
            -subj /CN=signer-test/ -days 1 -keyout keys/db.key -out keys/db.crt >/dev/null 2>&1
          for name in PK KEK; do cp keys/db.crt "keys/$name.crt"; done
          for name in PK KEK db; do printf enrollment > "keys/$name.auth"; done
          printf update-public-key > keys/update.pub
          jq -n --arg digest "$(sha256sum keys/db.crt | cut -d' ' -f1)" \
            --arg update "$(sha256sum keys/update.pub | cut -d' ' -f1)" \
            '{publicTrustDigests: {"PK.crt": $digest, "KEK.crt": $digest, "db.crt": $digest, "update.pub": $update}}' \
            > input/public-trust.json

          truncate -s 20M disk.raw
          sgdisk --new=1:1MiB:+16MiB --typecode=1:ef00 disk.raw
          esp="disk.raw@@1048576"
          mformat -i "$esp" -T 32768 -h 64 -s 32 ::
          for directory in EFI EFI/systemd EFI/BOOT EFI/Linux loader loader/entries; do
            mmd -i "$esp" "::$directory"
          done
          # A PE executable suffices here: this tests signing, not UKI bootability.
          efi=${systemd}/lib/systemd/boot/efi/systemd-bootx64.efi
          for name in EFI/systemd/systemd-bootx64.efi EFI/BOOT/BOOTX64.EFI EFI/Linux/ghaf-test.efi; do
            mcopy -i "$esp" "$efi" "::$name"
          done
          zstd disk.raw -o input/ghaf-image.raw.zst
          ghaf-sign-x86-image --key-dir keys --input input --output signed
          test -s signed/ghaf-image.bmap
          cmp input/public-trust.json signed/public-trust.json
          zstd -d signed/ghaf-image.raw.zst -o signed.raw
          for name in EFI/systemd/systemd-bootx64.efi EFI/BOOT/BOOTX64.EFI EFI/Linux/ghaf-test.efi; do
            mcopy -o -i signed.raw@@1048576 "::$name" check.efi
            sbverify --cert keys/db.crt check.efi
          done

          # A mixed Type-1/Type-2 ESP must never be published for enrollment.
          printf legacy > legacy.conf
          mcopy -i "$esp" legacy.conf ::loader/entries/legacy.conf
          zstd -f disk.raw -o input/ghaf-image.raw.zst
          ! ghaf-sign-x86-image --key-dir keys --input input --output rejected 2>error.log
          grep -F 'Type-1 boot entries remain' error.log
          test ! -e rejected

          printf mismatched > keys/update.pub
          ! ghaf-sign-x86-image --key-dir keys --input input --output wrong-trust 2>error.log
          grep -F 'Public trust mismatch' error.log
          test ! -e wrong-trust
          touch "$out"
        '';
  };
})
