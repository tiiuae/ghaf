# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  cryptsetup,
  jq,
  qemu-utils,
  runCommand,
  writeShellApplication,
}:
let
  imageCryptsetup = cryptsetup.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./offline-file-convert.patch ];
    configureFlags = (old.configureFlags or [ ]) ++ [
      "--with-luks2-lock-path=/tmp/cryptsetup"
    ];
    # The package's upstream suite includes privileged kernel-mapping tests.
    # This wrapper has a focused unprivileged regular-file round-trip below.
    doCheck = false;
  });

  ghaf-wrap-luks-image = writeShellApplication {
    name = "ghaf-wrap-luks-image";
    runtimeInputs = [
      coreutils
      imageCryptsetup
      jq
      qemu-utils
    ];
    text = builtins.readFile ./ghaf-wrap-luks-image.sh;
    meta = {
      description = "Wrap a regular-file image in LUKS2 without kernel devices";
      mainProgram = "ghaf-wrap-luks-image";
    };
  };
in
ghaf-wrap-luks-image.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.roundtrip =
      runCommand "ghaf-wrap-luks-image-roundtrip"
        {
          nativeBuildInputs = [
            ghaf-wrap-luks-image
            imageCryptsetup
          ];
        }
        ''
          truncate -s 64M plaintext.img
          printf 'ghaf-luks-start' | dd of=plaintext.img conv=notrunc status=none
          printf 'ghaf-luks-end' | dd of=plaintext.img bs=1 seek=$((64 * 1024 * 1024 - 13)) \
            conv=notrunc status=none
          printf 'test-passphrase' > key

          ghaf-wrap-luks-image \
            --image plaintext.img \
            --uuid 01234567-89ab-4cde-8fab-0123456789ab \
            --key-file key \
            --header-size-mib 32
          test "$(stat -c%s plaintext.img)" -eq $((96 * 1024 * 1024))
          test "$(du -B1 plaintext.img | cut -f1)" -lt $((40 * 1024 * 1024))

          mkdir -p /tmp/cryptsetup
          cryptsetup reencrypt --decrypt --force-offline-reencrypt \
            --batch-mode --key-file key \
            --header exported-header plaintext.img
          truncate -s 64M plaintext.img
          test "$(dd if=plaintext.img bs=1 count=15 status=none)" = ghaf-luks-start
          test "$(dd if=plaintext.img bs=1 skip=$((64 * 1024 * 1024 - 13)) \
            count=13 status=none)" = ghaf-luks-end
          touch "$out"
        '';
  };
})
