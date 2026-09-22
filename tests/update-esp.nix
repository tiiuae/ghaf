# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
pkgs.testers.nixosTest {
  name = "update-requires-esp";
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/partitioning/boot-health.nix ];
    options.microvm.vms = lib.mkOption {
      type = lib.types.attrs;
      default = { };
    };
    config = {
      ghaf.boot-health = {
        enable = true;
        requiredVmNames = [ ];
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-label/TEST-ESP";
        fsType = "vfat";
        options = [
          "nofail"
          "x-systemd.device-timeout=1s"
        ];
      };
      virtualisation.emptyDiskImages = [ 64 ];
      environment.systemPackages = [
        pkgs.ota-update
        pkgs.dosfstools
      ];
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.fail("findmnt --mountpoint /boot")
    command = "ota-update image {mode}install --manifest /run/missing.manifest --trusted-key /run/key --uki-trusted-cert /run/db.crt --target test"

    def rejected_esp():
        for mode in ["", "--dry-run "]:
            output = machine.fail(command.format(mode=mode) + " 2>&1")
            assert "requires a writable vfat ESP mounted at /boot" in output, output
        machine.succeed("systemctl reset-failed ghaf-boot-health")
        machine.fail("systemctl restart ghaf-boot-health")
        machine.succeed("journalctl -u ghaf-boot-health --no-pager | grep -F '/boot is not a mounted writable ESP'")
        machine.fail("test -e /persist/common/ota/accepted-generation")
        machine.fail("test -e /boot/EFI")

    with subtest("missing ESP does not prevent boot but blocks updates and acceptance"):
        rejected_esp()
    with subtest("a writable directory or wrong filesystem is not an ESP"):
        machine.succeed("mkdir -p /boot")
        rejected_esp()
        machine.succeed("mount -t tmpfs tmpfs /boot")
        rejected_esp()
        machine.succeed("umount /boot")
    with subtest("a read-only ESP blocks updates and acceptance"):
        machine.succeed("mkfs.vfat -n TEST-ESP /dev/vdb && udevadm settle && mount -o ro /dev/vdb /boot")
        rejected_esp()
    with subtest("a writable ESP reaches the remaining validation gates"):
        machine.succeed("mount -o remount,rw /boot")
        for mode in ["", "--dry-run "]:
            output = machine.fail(command.format(mode=mode) + " 2>&1")
            assert "requires a writable vfat ESP" not in output, output
            assert "missing.manifest" in output, output
        machine.succeed("systemctl reset-failed ghaf-boot-health")
        machine.fail("systemctl restart ghaf-boot-health")
        machine.succeed("journalctl -u ghaf-boot-health --no-pager | grep -F 'LUKS mapping crypted is not active'")
        machine.fail("test -e /persist/common/ota/accepted-generation")
  '';
}
