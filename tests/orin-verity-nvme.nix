# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
  writer = import ../modules/reference/hardware/jetpack/nvidia-jetson-orin/write-verity-nvme.nix {
    inherit pkgs;
  };
in
pkgs.testers.nixosTest {
  name = "orin-verity-nvme";
  nodes.machine = {
    virtualisation.emptyDiskImages = [
      128
      128
    ];
    environment.systemPackages = with pkgs; [
      writer
      cryptsetup
      dosfstools
      gptfdisk
      parted
    ];
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("truncate -s 4M /tmp/esp && mkfs.vfat -n ESP /tmp/esp && truncate -s 32M /tmp/app")
    machine.succeed("echo test-key >/tmp/key && cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /tmp/key /tmp/app")
    machine.succeed("echo ',,L' | sfdisk --label dos /dev/vdb")
    original = machine.succeed("sha256sum /dev/vdb /dev/vdc")
    with subtest("reject insufficient space before touching the disk"):
        machine.succeed("truncate -s 128M /tmp/oversized")
        machine.fail("write-verity-nvme /dev/vdb /tmp/esp /tmp/oversized")
        assert original == machine.succeed("sha256sum /dev/vdb /dev/vdc")
    with subtest("replace an MBR layout while preserving ESP and APP contents"):
        other = machine.succeed("sha256sum /dev/vdc")
        machine.succeed("write-verity-nvme /dev/vdb /tmp/esp /tmp/app && partprobe /dev/vdb && udevadm settle")
        assert "No problems found" in machine.succeed("sgdisk -v /dev/vdb")
        machine.succeed("cmp /tmp/esp /dev/vdb1 && cmp /tmp/app /dev/vdb2")
        machine.succeed("test $(blkid -s LABEL -o value /dev/vdb1) = ESP && cryptsetup open --key-file /tmp/key /dev/vdb2 flash-test && cryptsetup close flash-test")
        assert other == machine.succeed("sha256sum /dev/vdc")
    with subtest("reject an unlocked LUKS target even without mounts"):
        machine.succeed("cryptsetup open --key-file /tmp/key /dev/vdb2 active-target")
        written = machine.succeed("sha256sum /dev/vdb")
        machine.fail("write-verity-nvme /dev/vdb /tmp/esp /tmp/app")
        assert written == machine.succeed("sha256sum /dev/vdb")
        machine.succeed("cryptsetup close active-target")
    with subtest("reject mounted target partitions"):
        machine.succeed("mkdir -p /mnt && mount -o ro /dev/vdb1 /mnt")
        written = machine.succeed("sha256sum /dev/vdb")
        machine.fail("write-verity-nvme /dev/vdb /tmp/esp /tmp/app")
        assert written == machine.succeed("sha256sum /dev/vdb")
  '';
}
