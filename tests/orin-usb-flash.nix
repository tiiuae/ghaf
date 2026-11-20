# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
let
  prepare = pkgs.writeShellApplication {
    name = "prepare-test-images";
    text = ''
      mkdir -p "$WORKDIR/bootloader"
      cp /tmp/esp "$WORKDIR/bootloader/esp.img"
      cp /tmp/app "$WORKDIR/bootloader/system.img"
    '';
  };
  firmware = pkgs.writeShellApplication {
    name = "test-firmware";
    runtimeInputs = [
      pkgs.diffutils
      pkgs.systemd
    ];
    text = ''
      udevadm settle
      cmp /tmp/esp /dev/sda1
      cmp /tmp/app /dev/sda2
      printf '%s\n' "$@" >/run/firmware-called
    '';
  };
  flasher = import ../modules/reference/hardware/jetpack/nvidia-jetson-orin/usb-verity-flash.nix {
    config.system.build.prepareVerityFlashImages = prepare;
    pkgs = pkgs // {
      nvidia-jetpack.signedFlashScript = firmware;
    };
  };
in
pkgs.testers.nixosTest {
  name = "orin-usb-flash";
  nodes.machine = {
    virtualisation.emptyDiskImages = [ 128 ];
    environment.systemPackages = with pkgs; [
      flasher
      cryptsetup
      dosfstools
    ];
  };
  testScript = ''
    with open(machine.state_dir / "usb.img", "wb") as disk:
        disk.truncate(128 * 1024 * 1024)
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.send_monitor_command(f"drive_add 0 id=ssd,if=none,file={disk.name},format=raw")
    machine.send_monitor_command("device_add usb-storage,id=ssd,drive=ssd,serial=ghaf-test")
    machine.wait_until_succeeds("test $(lsblk -dn -o TRAN /dev/sda) = usb")
    machine.succeed("truncate -s 4M /tmp/esp && mkfs.vfat -n ESP /tmp/esp && truncate -s 32M /tmp/app && printf key >/tmp/key")
    machine.succeed("cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file /tmp/key /tmp/app")
    foreign = machine.succeed("sha256sum /dev/vdb")
    with subtest("reject missing or non-USB destinations before firmware access"):
        machine.fail("flash-verity-usb")
        machine.fail("flash-verity-usb --disk /dev/vdb")
        machine.succeed("test ! -e /run/firmware-called")
    with subtest("write a USB disk before invoking matching firmware"):
        machine.succeed("flash-verity-usb --disk /dev/sda -u --usb-instance 3-3")
        assert machine.succeed("cat /run/firmware-called").splitlines() == ["--usb-instance", "3-3"]
        machine.succeed("cryptsetup open --key-file /tmp/key /dev/sda2 usb-test && cryptsetup close usb-test")
        assert foreign == machine.succeed("sha256sum /dev/vdb")
    with subtest("refuse partitions and mounted USB disks without flashing firmware"):
        machine.succeed("rm /run/firmware-called && mkdir -p /mnt && mount -o ro /dev/sda1 /mnt")
        before = machine.succeed("sha256sum /dev/sda")
        machine.fail("flash-verity-usb --disk /dev/sda1")
        machine.fail("flash-verity-usb --disk /dev/sda")
        machine.succeed("test ! -e /run/firmware-called")
        assert before == machine.succeed("sha256sum /dev/sda")
  '';
}
