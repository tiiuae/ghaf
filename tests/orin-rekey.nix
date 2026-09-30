# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
  rekey = pkgs.writeShellApplication {
    name = "rekey-verity-image";
    runtimeInputs = with pkgs; [
      cryptsetup
      jq
    ];
    text = builtins.readFile ../modules/reference/hardware/jetpack/nvidia-jetson-orin/rekey-verity-image.sh;
  };
  check = pkgs.writeShellApplication {
    name = "check-orin-rekey";
    runtimeInputs = with pkgs; [
      cryptsetup
      jq
      coreutils
      rekey
    ];
    text = ''
      cd "$(mktemp -d)"
      umask 077
      printf manufacturer > manufacturer
      printf recovery > recovery
      printf device-unique > duk
      truncate -s 64M original.img
      cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
        --key-file manufacturer original.img
      cryptsetup open --key-file manufacturer original.img original
      printf preserved-payload | dd of=/dev/mapper/original conv=fsync status=none
      cryptsetup close original
      cryptsetup luksDump --dump-volume-key --batch-mode --key-file manufacturer \
        --volume-key-file original.key original.img

      for device in one two; do
        cp original.img "$device.img"
        rekey-verity-image "$device.img" manufacturer recovery
        cryptsetup luksDump --dump-volume-key --batch-mode --key-file manufacturer \
          --volume-key-file "$device.key" "$device.img"
        if cmp -s original.key "$device.key"; then exit 1; fi
        cryptsetup luksDump --dump-json-metadata "$device.img" | jq -e '.keyslots | keys == ["0", "1"]'
        cryptsetup open --test-passphrase --key-slot 1 --key-file recovery "$device.img"
        cryptsetup luksAddKey --key-file manufacturer "$device.img" duk
        cryptsetup luksRemoveKey --key-file manufacturer "$device.img"
        if cryptsetup open --test-passphrase --key-file manufacturer "$device.img"; then exit 1; fi
        cryptsetup open --key-file duk "$device.img" installed
        test "$(head -c 17 /dev/mapper/installed)" = preserved-payload
        cryptsetup close installed
        cryptsetup open --test-passphrase --key-slot 1 --key-file recovery "$device.img"
        if rekey-verity-image "$device.img" manufacturer recovery; then exit 1; fi
      done
      if cmp -s one.key two.key; then exit 1; fi
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "orin-per-flash-volume-key";
  nodes.machine = {
    boot.kernelModules = [
      "loop"
      "dm-crypt"
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("${check}/bin/check-orin-rekey", timeout=300)
  '';
}
