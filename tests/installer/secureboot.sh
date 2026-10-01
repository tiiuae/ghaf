#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

# shellcheck source=/dev/null
source "$BOOT_LIB"
mkdir keys mounts
export TMPDIR="$PWD/mounts"
openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes \
  -subj /CN=installer-test/ -days 1 -keyout keys/db.key -out keys/db.crt >/dev/null 2>&1
for name in PK KEK; do cp keys/db.crt "keys/$name.crt"; done
for name in PK KEK db; do
  cert-to-efi-sig-list keys/db.crt "keys/$name.esl"
  sign-efi-sig-list -k keys/db.key -c keys/db.crt "$name" "keys/$name.esl" "keys/$name.auth"
done

# Real signed PE sections exercise validation without needing a bootable kernel.
printf test >payload
objcopy --add-section .linux=payload --add-section .initrd=payload \
  --add-section .cmdline=payload --add-section .osrel=payload "$EFI_STUB" unsigned.efi
sbsign --key keys/db.key --cert keys/db.crt --output uki.efi unsigned.efi
sbsign --key keys/db.key --cert keys/db.crt --output loader.efi "$EFI_LOADER"

# Only mounting is substituted; entry parsing, PE inspection and signatures are real.
mount() {
  test "$1 $2 $3 $4 $5" = '-t vfat -o ro /dev/test-esp'
  cp -a esp/. "$6/"
}
umount() {
  rm -r "${1:?}/EFI" "$1/loader"
}
objdump() {
  touch objdump-called
  command objdump "$@"
}

reset_esp() {
  rm -rf esp
  rm -f objdump-called
  mkdir -p esp/EFI/{BOOT,Linux,nixos} esp/loader/entries
  cp loader.efi esp/EFI/BOOT/BOOTX64.EFI
  cp uki.efi esp/EFI/nixos/ghaf.efi
  cat >esp/loader/entries/ghaf.conf <<'EOF'
title NixOS
version Generation 1 NixOS
efi /EFI/nixos/ghaf.efi
options init=/unsigned-init
machine-id test
sort-key nixos
EOF
}
accepted() {
  verify_secureboot_esp /dev/test-esp keys
  test -z "$(ls -A "$TMPDIR")"
}
rejected() {
  if verify_secureboot_esp /dev/test-esp keys >output.log 2>&1; then
    echo "Unexpected acceptance: $1" >&2
    exit 1
  fi
  grep -F "$2" output.log
  test -z "$(ls -A "$TMPDIR")"
  echo "Rejected: $1"
}
rejected_without_inspection() {
  rejected "$1" 'EFI executable is not signed'
  test ! -e objdump-called
}

reset_esp
accepted
mv esp/EFI/nixos/ghaf.efi esp/EFI/Linux/ghaf.efi
rm esp/loader/entries/ghaf.conf
accepted
cp uki.efi esp/EFI/nixos/ghaf.efi
printf 'efi /EFI/nixos/ghaf.efi\n' >esp/loader/entries/ghaf.conf
accepted

reset_esp
sed -i 's|^efi .*|linux /EFI/nixos/kernel.efi\ninitrd /EFI/nixos/initrd.efi|' esp/loader/entries/ghaf.conf
rejected 'unsigned generation entry' 'Unsupported Secure Boot entry'

for directive in linux initrd devicetree devicetree-overlay uki-url; do
  reset_esp
  printf '%s /external\n' "$directive" >>esp/loader/entries/ghaf.conf
  rejected "$directive payload" 'Unsupported Secure Boot entry'
done
reset_esp
printf 'efi /EFI/nixos/ghaf.efi\n' >>esp/loader/entries/ghaf.conf
rejected 'duplicate efi directive' 'Unsupported Secure Boot entry'
reset_esp
printf 'title No executable\n' >esp/loader/entries/ghaf.conf
rejected 'missing efi directive' 'Unsupported Secure Boot entry'
reset_esp
rm esp/EFI/nixos/ghaf.efi
rejected 'missing executable' 'Invalid UKI path'
reset_esp
printf 'efi /../../uki.efi\n' >esp/loader/entries/ghaf.conf
rejected 'path outside ESP' 'Invalid UKI path'

for layout in entry auto; do
  reset_esp
  target=esp/EFI/nixos/ghaf.efi
  if [ "$layout" = auto ]; then
    rm esp/loader/entries/ghaf.conf
    target=esp/EFI/Linux/ghaf.efi
  fi
  cp loader.efi "$target"
  rejected "$layout signed non-UKI" 'Missing UKI sections'
  rm -f objdump-called
  cp unsigned.efi "$target"
  rejected_without_inspection "$layout unsigned UKI"
  printf 'not a PE binary' >"$target"
  rejected_without_inspection "$layout malformed executable"

  for section in .linux .initrd .cmdline .osrel; do
    for state in missing empty; do
      objcopy --remove-section "$section" unsigned.efi incomplete.efi
      if [ "$state" = empty ]; then
        objcopy --add-section "$section"=/dev/null incomplete.efi
      fi
      sbsign --key keys/db.key --cert keys/db.crt --output "$target" incomplete.efi
      rejected "$layout UKI with $state $section" 'Missing UKI sections'
    done
  done
done

openssl req -new -x509 -newkey rsa:2048 -sha256 -nodes \
  -subj /CN=wrong/ -days 1 -keyout wrong.key -out wrong.crt >/dev/null 2>&1
for target in EFI/nixos/ghaf.efi EFI/BOOT/BOOTX64.EFI; do
  reset_esp
  sbsign --key wrong.key --cert wrong.crt --output "esp/$target" unsigned.efi
  rejected_without_inspection "wrong signer: $target"
done
