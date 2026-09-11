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
    boot.kernelModules = [ "dm-crypt" ];
    services.lvm.enable = true;
    environment.etc."test-image".source = image;
    environment.systemPackages = with pkgs; [
      cryptsetup
      lvm2
      parted
    ];
    systemd.services.encrypt-test = {
      # The real initrd provides bash in /bin; a stage-2 service does not.
      path = [ pkgs.bash ];
      serviceConfig = {
        Type = "oneshot";
        Environment = "TERM=linux";
        inherit (host.boot.initrd.systemd.services.first-boot-encrypt.serviceConfig)
          ExecStart
          ExecStartPost
          ;
      };
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "x86-deferred-encryption";
  nodes = {
    one = node;
    two = node;
  };
  testScript = ''
    start_all()
    keys = []
    for machine in (one, two):
        machine.wait_for_unit("multi-user.target")
        machine.succeed("dd if=/etc/test-image of=/dev/vdb bs=4M conv=fsync status=none; partprobe /dev/vdb; udevadm settle")
        machine.succeed("test $(blkid -s TYPE -o value /dev/vdb2) = LVM2_member")
        machine.succeed("mkdir -p /mnt/esp; mount ${
          host.fileSystems."/boot".device
        } /mnt/esp; rm /mnt/esp/.ghaf-installer-encrypt; umount /mnt/esp")
        machine.fail("systemctl start encrypt-test")
        machine.succeed("mount /dev/vdb1 /mnt/esp; touch /mnt/esp/.ghaf-installer-encrypt; umount /mnt/esp; systemctl reset-failed encrypt-test")
        machine.succeed("systemctl start --no-block encrypt-test")
        machine.wait_for_console_text("Encryption Setup Complete!", timeout=300)
        machine.wait_for_shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("cryptsetup isLuks --type luks2 /dev/vdb2")
        machine.succeed("umask 077; printf ghaf > /run/test.key")
        machine.succeed("cryptsetup luksDump --dump-volume-key --batch-mode --key-file /run/test.key --volume-key-file /run/volume.key /dev/vdb2")
        keys.append(machine.succeed("sha256sum /run/volume.key").split()[0])
        machine.succeed("cryptsetup open --key-file /run/test.key /dev/vdb2 crypted; vgchange -ay pool")
        machine.succeed("test $(head -c 4 /dev/pool/root_1_deadbeef) = root")
        machine.succeed("test $(head -c 6 /dev/pool/verity_1_deadbeef) = verity")
        machine.succeed("mkdir -p /persist /mnt/esp; mount /dev/pool/persist /persist; test -e /persist/.encryption-applied")
        machine.succeed("mount /dev/vdb1 /mnt/esp; test ! -e /mnt/esp/.ghaf-installer-encrypt")
        machine.succeed("systemctl start encrypt-test")
        machine.succeed("cryptsetup luksDump --dump-volume-key --batch-mode --key-file /run/test.key --volume-key-file /run/after.key /dev/vdb2; cmp /run/volume.key /run/after.key")
    assert keys[0] != keys[1], "Two installs retained the same volume key"
  '';
}
