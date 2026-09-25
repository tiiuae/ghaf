# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, self }:
let
  host = self.nixosConfigurations.intel-laptop-debug-secure-ab.config;
  image = pkgs.runCommand "x86-deferred-test-disk.raw" { nativeBuildInputs = [ pkgs.zstd ]; } ''
    zstd -d ${pkgs.ghaf-prepare-x86-verity-disk.tests.image}/ghaf-image.raw.zst -o "$out"
  '';
  node = {
    virtualisation = {
      memorySize = 2048;
      emptyDiskImages = [ 4728 ];
    };
    boot.supportedFilesystems = [ "btrfs" ];
    boot.kernelModules = [
      "dm-crypt"
      "dm-verity"
    ];
    services.lvm.enable = true;
    environment.etc."test-image".source = image;
    environment.systemPackages = with pkgs; [
      cryptsetup
      jq
      lvm2
      parted
    ];
    systemd.services.first-boot-encrypt = {
      inherit (host.boot.initrd.systemd.services.first-boot-encrypt) before requiredBy;
      # The real initrd provides bash in /bin; a stage-2 service does not.
      path = [ pkgs.bash ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "TERM=linux";
        # Let verity win the race when the production ordering is missing.
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
        inherit (host.boot.initrd.systemd.services.first-boot-encrypt.serviceConfig)
          ExecStart
          ExecStartPost
          ;
      };
    };
    systemd.services."systemd-veritysetup@nix-store" = {
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.cryptsetup}/bin/veritysetup close nix-store";
      };
      script = ''
        ${pkgs.cryptsetup}/bin/veritysetup open /dev/pool/root_1_deadbeef nix-store \
          /dev/pool/verity_1_deadbeef "$(cat /run/test-roothash)"
      '';
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "x86-deferred-encryption";
  nodes = {
    one = node;
    two = node;
    three = node;
  };
  testScript = ''
    start_all()
    keys = []
    for machine in (one, two, three):
        machine.wait_for_unit("multi-user.target")
        machine.succeed("dd if=/etc/test-image of=/dev/vdb bs=4M conv=fsync status=none; partprobe /dev/vdb; udevadm settle")
        machine.succeed("test $(blkid -s TYPE -o value /dev/vdb2) = LVM2_member")
        machine.succeed("vgchange -ay pool; veritysetup format /dev/pool/root_1_deadbeef /dev/pool/verity_1_deadbeef --root-hash-file /run/test-roothash")
        root_hash = machine.succeed("cat /run/test-roothash").strip()
        if machine != one:
            machine.succeed("umask 077; printf ghaf > /run/test.key; vgchange -an pool; pvresize --yes --setphysicalvolumesize $(( $(blockdev --getsize64 /dev/vdb2) - 32 * 1024 * 1024 ))B /dev/vdb2")
            mode = "--init-only" if machine == two else ""
            machine.succeed(f"cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M --key-file /run/test.key --batch-mode {mode} /dev/vdb2")
        machine.succeed("mkdir -p /mnt/esp")
        if machine != three:
            machine.succeed("mount ${
              host.fileSystems."/boot".device
            } /mnt/esp; rm /mnt/esp/.ghaf-installer-encrypt; umount /mnt/esp")
            machine.fail("systemctl start first-boot-encrypt systemd-veritysetup@nix-store")
            machine.succeed("test ! -e /dev/mapper/nix-store")
            machine.succeed("mount /dev/vdb1 /mnt/esp; touch /mnt/esp/.ghaf-installer-encrypt; umount /mnt/esp; systemctl reset-failed")
        machine.succeed("systemctl start --no-block first-boot-encrypt systemd-veritysetup@nix-store")
        machine.wait_for_console_text("Encryption Setup Complete!", timeout=300)
        machine.wait_for_shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("cryptsetup isLuks --type luks2 /dev/vdb2")
        machine.succeed("cryptsetup luksDump --dump-json-metadata /dev/vdb2 | jq -e 'all(.keyslots[]; .type != \"reencrypt\") and all(.segments[]; .type == \"crypt\")'")
        machine.succeed("umask 077; printf ghaf > /run/test.key")
        machine.succeed("cryptsetup luksDump --dump-volume-key --batch-mode --key-file /run/test.key --volume-key-file /run/volume.key /dev/vdb2")
        keys.append(machine.succeed("sha256sum /run/volume.key").split()[0])
        machine.succeed("cryptsetup open --key-file /run/test.key /dev/vdb2 crypted; vgchange -ay pool")
        machine.succeed("test $(head -c 4 /dev/pool/root_1_deadbeef) = root")
        machine.succeed(f"echo {root_hash} > /run/test-roothash")
        machine.succeed("mkdir -p /persist /mnt/esp; mount /dev/pool/persist /persist; test -e /persist/.encryption-applied")
        machine.succeed("mount /dev/vdb1 /mnt/esp; test ! -e /mnt/esp/.ghaf-installer-encrypt")
        machine.succeed("systemctl start first-boot-encrypt systemd-veritysetup@nix-store")
        machine.succeed("test $(head -c 4 /dev/mapper/nix-store) = root")
        machine.succeed("cryptsetup luksDump --dump-volume-key --batch-mode --key-file /run/test.key --volume-key-file /run/after.key /dev/vdb2; cmp /run/volume.key /run/after.key")
    assert len(set(keys)) == 3, "Installs retained the same volume key"
  '';
}
